"""Check the QuestieDB adapter against a double of QuestieDB's documented contract-4 API in Lua 5.1; not a WoW runtime test."""

from compass_harness import client

# QuestieDB's public read semantics (docs/api.md, Types/*.t.lua): numeric getters return 0, empty tables come back nil
# except a known quest's objectives and givers, unknown ids are nil everywhere, every table read is a fresh copy, GetAll
# returns a packed table, and the area-to-UiMap table is Lua source the consumer loads. The quest log, item icon and
# timer doubles follow the client's generated documentation (QuestInfo, QuestObjectiveInfo, QuestPOIMapInfo).
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
mock.done,mock.log,mock.rep,mock.skills,mock.spells={},{},{},{},{}
mock.entries,mock.objectives,mock.complete,mock.ready,mock.failed,mock.pins,mock.icons,mock.timers={},{},{},{},{},{},{},{}
mock.reads={}
local function Copy(value)
 if type(value)~="table" then return value end
 local copy={} for key,field in pairs(value) do copy[key]=Copy(field) end return copy
end
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
C_QuestLog.GetNumQuestLogEntries=function()
 local quests=0 for _,entry in ipairs(mock.entries) do if not entry.isHeader then quests=quests+1 end end
 return #mock.entries,quests
end
C_QuestLog.GetInfo=function(index) return mock.entries[index] end
C_QuestLog.GetQuestObjectives=function(id) mock.logReads=(mock.logReads or 0)+1 return Copy(mock.objectives[id] or {}) end
C_QuestLog.IsComplete=function(id) return mock.complete[id]==true end
C_QuestLog.ReadyForTurnIn=function(id) return mock.ready[id] end
C_QuestLog.IsFailed=function(id) return mock.failed[id]==true end
C_QuestLog.GetQuestsOnMap=function(mapID) return Copy(mock.pins[mapID] or {}) end
C_Item.GetItemIconByID=function(id) return mock.icons[id] end
C_Timer.After=function(seconds,callback) mock.timers[#mock.timers+1]={at=mock.now+seconds,run=callback} end
C_Reputation.GetFactionDataByID=function(id) return mock.rep[id] and {currentStanding=mock.rep[id]} end
C_SkillInfo={GetSkillLineInfoByID=function(id) return mock.skills[id] and {skillID=id,rank=mock.skills[id]} end}
C_SpellBook=C_SpellBook or {}
C_SpellBook.IsSpellKnown=function(id) return mock.spells[id]==true end
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
 [23]={questLevel=28,requiredSkill={171,50}},[24]={questLevel=28,breadcrumbForQuestId=17},[25]={requiredLevel=40,questLevel=40},
 [26]={questLevel=28,requiredSpell=2259},[27]={questLevel=28,requiredSpell=-2259},[28]={questLevel=28,requiredSpecialization=20219},
 [29]={questLevel=28,requiredRanks={{171,300},{182,75}}}}
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
-- Log quests: creatures 50 and 51 share one camp cell, item 70 drops from both and sits in crate 60.
Npcs[50]={name="Kobold Miner",spawns={[100]={{11,11},{11.5,11.5},{31,31}},[200]={{41,41}}}}
Npcs[51]={name="Kobold Tunneler",spawns={[100]={{11.2,11.2},{81,81}}}}
Npcs[52]={name="Kobold Credit"}
Objects[60]={name="Ore Crate",spawns={[100]={{21,21}}}}
Items={[70]={name="Kobold Candle",npcDrops={50,51},objectDrops={60},vendors={2}},[71]={name="Vendor Token",vendors={2}}}
Quests[40]={questLevel=28,objectives={{{50,nil,0}}},finishedBy={{1}}}
Quests[41]={questLevel=28,objectives={nil,{{60,nil,0}}},finishedBy={{1}}}
Quests[42]={questLevel=28,objectives={nil,nil,{{70,nil,0}}},finishedBy={{1},{7}}}
Quests[43]={questLevel=28,objectives={nil,nil,nil,nil,{{{50,51},52,"Kobolds slain",0}}}}
Quests[44]={questLevel=28,triggerEnd={"Explore the mine",{[100]={{33,44}}}}}
Quests[45]={questLevel=28,objectives={{{50,nil,0}},nil,{{70,nil,0}}}}
Quests[46]={questLevel=28,objectives={nil,nil,{{71,nil,0}}}}
Quests[47]={questLevel=28,finishedBy={{1}}}
-- QuestieDB's quest-side starters, derived from the doubles' NPC and object lists at read time.
local function StartedBy(questID)
 local npcs,objects,items
 for id,row in pairs(Items) do for _,q in ipairs(row.questStarts or {}) do if q==questID then items=items or {} items[#items+1]=id end end end
 for id,row in pairs(Npcs) do for _,q in ipairs(row.questStarts or {}) do if q==questID then npcs=npcs or {} npcs[#npcs+1]=id end end end
 for id,row in pairs(Objects) do for _,q in ipairs(row.questStarts or {}) do if q==questID then objects=objects or {} objects[#objects+1]=id end end end
 if npcs then table.sort(npcs) end
 if items then table.sort(items) end
 return {npcs,objects,items}
end
-- Table reads count per field and entity in mock.reads, so a scenario can prove a read happened once.
local function Entity(store,numeric,fields)
 local entity={GetAllIds=function()
  mock.idReads=(mock.idReads or 0)+1
  local ids={} for id in pairs(store) do ids[#ids+1]=id end table.sort(ids) return ids
 end}
 for _,field in ipairs(fields) do
  entity[field]=function(id) local row=store[id] if not row then return nil end
   local value=row[field] if value==nil and numeric[field] then return 0 end
   if type(value)~="table" then return value end
   if mock.broken and mock.broken[field..id] then error("broken "..field..id) end
   mock.reads[field]=(mock.reads[field] or 0)+1; mock.reads[field..id]=(mock.reads[field..id] or 0)+1
   return Copy(value) end
 end
 return entity
end
local NPC_FIELDS={"name","questStarts","npcFlags","spawns","friendlyToFaction"}
local ZoneDB={private={areaIdToUiMapId="return {[100]=3,[200]=5,[300]=3}",
 dungeons={[718]={"Wailing Caverns",nil,17,{{300,46,36.5}}},[9999]={"Utgarde Keep",nil,495,{{300,10,10}}}}},
 instanceIdToAreaId={[43]=718,[574]=9999}}
LibQuestieDB={
 RequireContract=function(v) return v>=1 and v<=(mock.contract or 4) end,
 Npc=Entity(Npcs,{npcFlags=1},NPC_FIELDS),Object=Entity(Objects,{},NPC_FIELDS),
 Item=Entity(Items,{},{"name","npcDrops","objectDrops","vendors"}),
 ObjectiveFirst={killCreditObjectiveFirst={},objectObjectiveFirst={},itemObjectiveFirst={},eventObjectiveFirst={},
  spellObjectiveFirst={}},
 Quest={name=function(id) return Quests[id] and "DB "..id end,
  GetAllIds=function() local ids={} for id in pairs(Quests) do ids[#ids+1]=id end table.sort(ids) return ids end,
  startedBy=function(id) if mock.brokenStarters then error("broken starters") end return Quests[id] and StartedBy(id) end,
  GetAll=function(id,keys)
  local row=Quests[id] if not row then return nil end
  mock.reads["quest"..id]=(mock.reads["quest"..id] or 0)+1
  local values={n=#keys} for i,key in ipairs(keys) do local v=row[key] if v==nil and NUMERIC[key] then v=0 end
   if v==nil and (key=="objectives" or key=="finishedBy") then v={} end values[i]=Copy(v) end
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
function Available(id) local A=Addon.CompassQuestieAvailability return A.IsAvailable(A.Context(LibQuestieDB,P.questLevelRange,{},P),id) end
-- The quest log as the client lists it: a zone header, then each accepted quest with its live objectives.
function Take(id,objectives,level)
 if #mock.entries==0 then mock.entries[1]={title="Zone",questLogIndex=1,questID=0,level=0,isHeader=true,isHidden=false} end
 local index=#mock.entries+1
 mock.entries[index]={title="Quest "..id,questLogIndex=index,questID=id,level=level or 28,isHeader=false,isHidden=false}
 mock.log[id],mock.objectives[id]=index,objectives or {}
end
-- Objective icons draw only for a quest whose hint the player turned on, so most scenarios accept a quest with it.
function Accept(id,objectives,level) Take(id,objectives,level); Addon.CompassQuestieHints.Add(P,id) end
function Goal(text,kind,finished)
 return {text=text,type=kind,finished=finished==true,numFulfilled=finished and 1 or 0,numRequired=1}
end
function Advance(seconds)
 mock.now=mock.now+seconds
 local due={}
 for index=#mock.timers,1,-1 do
  if mock.timers[index].at<=mock.now then table.insert(due,1,table.remove(mock.timers,index)) end
 end
 for _,timer in ipairs(due) do timer.run() end
end
-- Objective places prepare on their own driver frame; this runs it until it is idle and counts its frames.
function Prepare()
 local state,steps=P.compassQuestiePrepare,0
 while state and state.driving and steps<10000 do state.driver.OnUpdate(state.driver,0.016); steps=steps+1 end
 return steps
end
-- One host collection, repeated once preparation finishes, as the host does when the provider invalidates.
function Collect(mapID)
 local rows=P:CollectCompassQuestieMapRows(mapID or 3)
 if Prepare()>0 then rows=P:CollectCompassQuestieMapRows(mapID or 3) end
 return rows
end
function Pick(rows,prefix)
 local found={}
 for _,row in ipairs(rows) do if row.key:find(prefix,1,true)==1 then found[#found+1]=row end end
 table.sort(found,function(a,b) return a.key<b.key end)
 return found
end
function RowKeys(rows,prefix)
 local keys={} for _,row in ipairs(Pick(rows,prefix)) do keys[#keys+1]=row.key end return table.concat(keys,",")
end
function Texts(row)
 local texts={} for _,line in ipairs(row.lines) do texts[#texts+1]=line.text end return table.concat(texts,"|")
end
-- The host's context menu as Compass fills it for one row: a title, buttons and an optional divider.
function RowMenu(provider,key)
 local menu={rows={}}
 function menu:CreateTitle(text) self.title=text end
 function menu:CreateButton(text,run) self.rows[#self.rows+1]={text=text,run=run} end
 function menu:CreateDivider() self.divided=true end
 provider.Menu(key,menu)
 return menu
end
-- The entries Compass adds to a menu of the host's for a quest the host draws itself.
function QuestMenu(provider,questID)
 local menu={rows={}}
 function menu:CreateTitle(text) self.title=text end
 function menu:CreateButton(text,run) self.rows[#self.rows+1]={text=text,run=run} end
 function menu:CreateDivider() self.divided=true end
 provider.QuestMenu(questID,menu)
 return menu
end
-- A hosted Compass keeps per-character data in the host plugin's store.
function HostStore()
 P.store={}
 function P:GetCharData(key) return self.store[key] end
 function P:SetCharData(key,value) self.store[key]=value end
end
function Host()
 local calls={invalidate=0,register=0}
 Addon.OrbitHost={ExternalUIHost={mapPointProviderVersion=1},MapPOICompanion={
  Register=function(_,provider) calls.register=calls.register+1 calls.provider=provider return true end,
  Unregister=function() return true end,
  Invalidate=function(_,provider) assert(provider==calls.provider) calls.invalidate=calls.invalidate+1 end}}
 P:ConnectCompassMapPoints()
 return calls
end
'''

CASES = {
    "a host map receives one map's available givers as rows, and nothing while the index builds": '''
        mock.done[11]=true
        assert(P:CollectCompassQuestieMapRows(3)==nil,"an unbuilt index answered")
        Drain()
        local rows=P:CollectCompassQuestieMapRows(3)
        local keys={} for _,row in ipairs(rows) do keys[#keys+1]=row.key end table.sort(keys)
        assert(table.concat(keys,",")=="giver:npc:1:1,giver:object:7:1", table.concat(keys,","))
        local row=rows[1].key=="giver:npc:1:1" and rows[1] or rows[2]
        assert(row.name=="Giver" and row.atlas=="QuestNormal" and row.x==0.5 and row.description=="Quest 10")
        assert(row.scale==0.75,"a host map giver is not drawn at three quarters size")
        assert(row.lines[1].text:find("Quest 10",1,true))
        assert(#P:CollectCompassQuestieMapRows(5)==1 and #P:CollectCompassQuestieMapRows(99)==0)
        P.showQuestOffers=false
        assert(#P:CollectCompassQuestieMapRows(3)==0,"hidden Available Quests still reached the host map")
    ''',
    "the host's point provider is registered while integrations run and told when givers change": '''
        local calls={register=0,unregister=0,invalidate=0}
        local points={Register=function(_,p) calls.register=calls.register+1 calls.provider=p return true end,
            Unregister=function(_,p) calls.unregister=calls.unregister+1 assert(p==calls.provider) return true end,
            Invalidate=function(_,p) calls.invalidate=calls.invalidate+1 assert(p==calls.provider) end}
        Addon.OrbitHost={ExternalUIHost={mapPointProviderVersion=1},MapPOICompanion=points}
        P:ConnectCompassMapPoints()
        assert(calls.register==1 and type(calls.provider.Collect)=="function" and calls.provider.name~="")
        Drain()
        local before=calls.invalidate
        P:InvalidateCompassSource("QUEST_ACCEPTED")
        assert(calls.invalidate==before+1,"an accepted quest left the host's givers stale")
        local rows,refresh=calls.provider.Collect(3)
        assert(type(rows)=="table" and refresh==60)
        P:DisconnectCompassMapPoints()
        assert(calls.unregister==1)
        Addon.OrbitHost={ExternalUIHost={mapPointProviderVersion=2},MapPOICompanion=points}
        P:ConnectCompassMapPoints()
        assert(calls.register==1,"an unknown host capability version was used")
        Addon.OrbitHost=nil
    ''',
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
        assert(not Available(23), "a profession the character never learned")
        assert(not Available(26) and Available(27), "a required spell is unknown, a forbidden one is absent")
        assert(not Available(28) and not Available(29), "no specialization and neither alternative rank")
        assert(not Available(24), "breadcrumb target taken")
        assert(not Available(25), "too low level")
        assert(not Available(999), "unknown quest")
        mock.done[99]=true; assert(Available(12), "prerequisite done")
        mock.done[22]=true; assert(Available(22), "repeatable stays available")
        mock.skills[171]=49; assert(not Available(23), "skill below the required rank")
        mock.skills[171]=50; assert(Available(23), "skill at the required rank")
        mock.spells[2259]=true; assert(Available(26) and not Available(27), "the spell is now known")
        mock.spells[20219]=true; assert(Available(28), "specialization learned")
        mock.skills[182]=75; assert(Available(29), "one alternative rank is enough")
        C_SkillInfo=nil; assert(not Available(23) and not Available(29), "no skill reader confirms nothing")
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
    "creature objectives show that NPC's spawns as kill icons, smaller than givers": '''
        Accept(40,{Goal("Kobold Miner slain: 0/8","monster")}); Drain()
        local rows=Collect(3)
        assert(RowKeys(rows,"objective:")=="objective:40:1:164,objective:40:1:492", RowKeys(rows,"objective:"))
        local row=Pick(rows,"objective:40:1:164")[1]
        assert(row.atlas=="Crosshair_attack_32" and row.texture==nil and row.scale==0.6 and row.name=="Kobold Miner")
        assert(math.abs(row.x-0.1125)<1e-9 and math.abs(row.y-0.1125)<1e-9, row.x)
        assert(Texts(row)=="[28] Quest 40|Kobold Miner slain: 0/8", Texts(row))
        assert(row.lines[1].g==0.75 and row.lines[2].r==1, "the title lost its difficulty colour")
        assert(#Pick(rows,"giver:")==2 and #Pick(rows,"turnin:")==0)
        assert(RowKeys(Collect(5),"objective:")=="objective:40:1:656", RowKeys(Collect(5),"objective:"))
        assert(#Pick(Collect(99),"objective:")==0)
    ''',
    "object objectives show that object's spawns": '''
        Accept(41,{Goal("Ore Crate opened: 0/1","object")}); Drain()
        local rows=Pick(Collect(3),"objective:")
        assert(#rows==1 and rows[1].key=="objective:41:1:328" and rows[1].atlas=="Crosshair_interact_32")
        assert(rows[1].name=="Ore Crate" and Texts(rows[1])=="[28] Quest 41|Ore Crate opened: 0/1", Texts(rows[1]))
    ''',
    "item objectives show droppers and containers under the item's own icon, never a vendor beside them": '''
        Accept(42,{Goal("Kobold Candle: 0/8","item")}); Drain()
        local rows=Collect(3)
        assert(RowKeys(rows,"objective:")=="objective:42:1:1312,objective:42:1:164,objective:42:1:328,objective:42:1:492",
            RowKeys(rows,"objective:"))
        local row=Pick(rows,"objective:42:1:164")[1]
        assert(row.atlas=="Crosshair_lootall_32" and row.texture==nil, "an item without a client icon lost its art")
        assert(row.name=="Kobold Candle" and row.scale==0.6)
        assert(Texts(row)=="[28] Quest 42|Kobold Candle: 0/8|Kobold Miner, Kobold Tunneler", Texts(row))
        assert(row.lines[3].r==0.7, "the source line is not muted")
        assert(Texts(Pick(rows,"objective:42:1:328")[1])=="[28] Quest 42|Kobold Candle: 0/8|Ore Crate")
        mock.icons[70]=134400
        row=Pick(Collect(3),"objective:42:1:164")[1]
        assert(row.texture==134400 and row.atlas==nil, "the item's own icon was not used once the client had it")
    ''',
    "an item with no other source shows its vendor": '''
        Accept(46,{Goal("Vendor Token: 0/1","item")}); Drain()
        local rows=Pick(Collect(3),"objective:46:1:")
        assert(#rows==1 and rows[1].x==0.2 and rows[1].y==0.3 and Texts(rows[1]):find("Innkeeper Pala",1,true))
    ''',
    "an item reads at most sixteen sources": '''
        local drops={}
        for id=2000,2039 do
            Npcs[id]={name="Dropper "..id,spawns={[100]={{(id-2000)*2.5+1.3,51.3}}}}; drops[#drops+1]=id
        end
        Items[72]={name="Flood",npcDrops=drops}; Quests[48]={questLevel=28,objectives={nil,nil,{{72,nil,0}}}}
        Accept(48,{Goal("Flood: 0/1","item")}); Drain()
        assert(#Pick(Collect(3),"objective:48:1:")==16)
        assert(mock.reads.spawns2015==1 and mock.reads.spawns2016==nil, "a seventeenth source was read")
    ''',
    "kill-credit objectives show the listed NPCs under the credit's own text": '''
        Accept(43,{Goal("Kobolds slain: 0/10","monster")}); Drain()
        local rows=Collect(3)
        assert(RowKeys(rows,"objective:")=="objective:43:1:1312,objective:43:1:164,objective:43:1:492",
            RowKeys(rows,"objective:"))
        local row=Pick(rows,"objective:43:1:164")[1]
        assert(row.name=="Kobolds slain" and row.atlas=="Crosshair_attack_32")
        assert(Texts(row)=="[28] Quest 43|Kobolds slain: 0/10|Kobold Miner, Kobold Tunneler", Texts(row))
    ''',
    "an exploration trigger shows its point": '''
        Accept(44,{Goal("Explore the mine","event")}); Drain()
        local rows=Pick(Collect(3),"objective:")
        assert(#rows==1 and rows[1].key=="objective:44:1:537" and rows[1].atlas=="VignetteEvent", rows[1].key)
        assert(rows[1].x==0.33 and rows[1].y==0.44 and rows[1].name=="Explore the mine")
        assert(Texts(rows[1])=="[28] Quest 44|Explore the mine", Texts(rows[1]))
    ''',
    "a trigger follows a quest's other objectives unless a hint lists it first": '''
        Quests[50]={questLevel=28,objectives={{{50,nil,0}}},triggerEnd={"Reach the camp",{[100]={{33,44}}}}}
        Quests[51]={questLevel=28,objectives={{{50,nil,0}}},triggerEnd={"Scout the camp",{[100]={{33,44}}}}}
        LibQuestieDB.ObjectiveFirst.eventObjectiveFirst[51]=true
        Accept(50,{Goal("Kobold Miner slain: 8/8","monster",true),Goal("Reach the camp","event")})
        Accept(51,{Goal("Scout the camp","event",true),Goal("Kobold Miner slain: 0/8","monster")}); Drain()
        local keys=RowKeys(Collect(3),"objective:")
        assert(keys=="objective:50:2:537,objective:51:2:164,objective:51:2:492", keys)
    ''',
    "objective art the client lacks falls back to its bonus-objective star": '''
        mock.missingArt={Crosshair_attack_32=true}
        Accept(40,{Goal("Kobold Miner slain: 0/8","monster")}); Drain()
        assert(Pick(Collect(3),"objective:")[1].atlas=="Bonus-Objective-Star")
    ''',
    "finished objectives are skipped by their index in the client's list": '''
        Accept(45,{Goal("Kobold Miner slain: 8/8","monster",true),Goal("Kobold Candle: 2/8","item")}); Drain()
        local rows=Collect(3)
        assert(RowKeys(rows,"objective:45:1:")=="" and #Pick(rows,"objective:45:2:")==4, RowKeys(rows,"objective:"))
        assert(Texts(Pick(rows,"objective:45:2:492")[1])=="[28] Quest 45|Kobold Candle: 2/8|Kobold Miner")
    ''',
    "a hint that names the group a quest lists first reorders the match": '''
        LibQuestieDB.ObjectiveFirst.itemObjectiveFirst[45]=true
        Accept(45,{Goal("Kobold Candle: 8/8","item",true),Goal("Kobold Miner slain: 0/8","monster")}); Drain()
        local rows=Collect(3)
        assert(RowKeys(rows,"objective:")=="objective:45:2:164,objective:45:2:492", RowKeys(rows,"objective:"))
        assert(Pick(rows,"objective:45:2:164")[1].atlas=="Crosshair_attack_32")
    ''',
    "objectives that do not line up with the client's list all show": '''
        Accept(45,{Goal("Something else: 1/1","monster",true)}); Drain()
        local expected="objective:45:1:164,objective:45:1:492,objective:45:2:1312,objective:45:2:328"
        local rows=Collect(3)
        assert(RowKeys(rows,"objective:")==expected, RowKeys(rows,"objective:"))
        assert(Texts(Pick(rows,"objective:45:1:164")[1])=="[28] Quest 45|Kobold Miner|Kobold Candle|Kobold Miner, Kobold Tunneler",
            Texts(Pick(rows,"objective:45:1:164")[1]))
        mock.objectives[45]={Goal("Kobold Candle: 8/8","item",true),Goal("Kobold Miner slain: 0/8","monster")}
        P:InvalidateCompassSource("QUEST_ACCEPTED")
        assert(RowKeys(Collect(3),"objective:")==expected, "a list in another order hid an objective as finished")
    ''',
    "a complete quest shows its turn-in instead of its objectives": '''
        Accept(40,{Goal("Kobold Miner slain: 8/8","monster",true)}); mock.complete[40]=true; Drain()
        local rows=Collect(3)
        assert(RowKeys(rows,"objective:")=="" and RowKeys(rows,"turnin:")=="turnin:n1:820", RowKeys(rows,"turnin:"))
        local row=Pick(rows,"turnin:")[1]
        assert(row.atlas=="UI-QuestIcon-TurnIn-Normal" and row.scale==nil and row.name=="Giver")
        assert(row.x==0.5 and row.y==0.5 and Texts(row)=="[28] Quest 40", Texts(row))
    ''',
    "quests ending at one finisher share its icon, and object finishers show too": '''
        Accept(40,{}); Accept(42,{}); mock.complete[40]=true; mock.ready[42]=true; Drain()
        local rows=Pick(Collect(3),"turnin:")
        assert(#rows==2 and rows[1].key=="turnin:n1:820" and rows[2].key:find("turnin:o7:",1,true)==1, RowKeys(rows,"turnin:"))
        assert(Texts(rows[1])=="[28] Quest 40|[28] Quest 42" and Texts(rows[2])=="[28] Quest 42", Texts(rows[1]))
        assert(rows[2].name=="Wanted Poster")
    ''',
    "a quest with no objectives at all shows its turn-in at once": '''
        Accept(47,{}); Drain()
        assert(RowKeys(Collect(3),"turnin:")=="turnin:n1:820")
    ''',
    "finishers of the other faction, hostile ones and failed quests stay hidden": '''
        Quests[40].finishedBy={{5,8}}; Accept(40,{}); mock.complete[40]=true
        Accept(41,{Goal("Ore Crate opened: 0/1","object")}); mock.failed[41]=true; Drain()
        local rows=Collect(3)
        assert(#Pick(rows,"turnin:")==0 and #Pick(rows,"objective:")==0)
    ''',
    "a turn-in the client already pins is left to the client": '''
        Accept(40,{}); mock.complete[40]=true; Drain()
        local pin={questID=40,numObjectives=0,mapID=3,x=0.52,y=0.5,isQuestStart=false,isDaily=false,
            isCombatAllyQuest=false,isMeta=false,inProgress=true,isMapIndicatorQuest=false}
        mock.pins[3]={pin}
        assert(#Pick(Collect(3),"turnin:")==0, "a turn-in doubled the client's own pin")
        pin.x=0.54
        assert(#Pick(Collect(3),"turnin:")==1, "a pin more than 3% of the map away hid the turn-in")
        pin.x,pin.questID=0.5,41
        assert(#Pick(Collect(3),"turnin:")==1, "another quest's pin hid the turn-in")
    ''',
    "an objective clusters to one icon per cell, keeps its densest 24 and holds their places": '''
        local points={}
        for cell=0,29 do for point=1,cell+1 do points[#points+1]={2.5*cell+1.3,61.3+point*0.01} end end
        Npcs[53]={name="Swarm",spawns={[100]=points}}; Quests[49]={questLevel=28,objectives={{{53,nil,0}}}}
        Accept(49,{Goal("Swarm slain: 0/50","monster")}); Drain()
        local rows=Pick(Collect(3),"objective:49:1:")
        assert(#rows==24, #rows)
        for _,row in ipairs(rows) do
            local cell=tonumber(row.key:match(":(%d+)$"))
            assert((cell-24)/40>=6, "a sparse cell outranked a dense one: "..row.key)
        end
        local dense=Pick(rows,"objective:49:1:1184")[1]
        assert(math.abs(dense.x-0.738)<1e-9 and math.abs(dense.y-0.61455)<1e-9, dense.y)
        local again=Pick(Collect(3),"objective:49:1:")
        for index,row in ipairs(rows) do
            assert(again[index].key==row.key and again[index].x==row.x and again[index].y==row.y, row.key)
        end
    ''',
    "one map shows at most 240 objective icons, trimmed evenly across objectives": '''
        for quest=1,12 do
            local points={}
            for cell=0,23 do for point=1,24-cell do points[#points+1]={2.5*cell+1.3,quest*5+1.3+point*0.001} end end
            Npcs[3000+quest]={name="Pack "..quest,spawns={[100]=points}}
            Quests[500+quest]={questLevel=28,objectives={{{3000+quest,nil,0}}}}
            Accept(500+quest,{Goal("Pack slain","monster")})
        end
        Drain()
        local rows=Collect(3)
        assert(#Pick(rows,"objective:")==240, #Pick(rows,"objective:"))
        for quest=1,12 do assert(#Pick(rows,"objective:"..(500+quest)..":1:")==20, quest) end
    ''',
    "quests that share a source at a spot merge into one icon with a section each": '''
        Accept(40,{Goal("Kobold Miner slain: 0/8","monster")}); Accept(42,{Goal("Kobold Candle: 0/8","item")}); Drain()
        local rows=Collect(3)
        assert(RowKeys(rows,"objective:")=="objective:40:1:164,objective:40:1:492,objective:42:1:1312,objective:42:1:328",
            RowKeys(rows,"objective:"))
        local row=Pick(rows,"objective:40:1:164")[1]
        assert(row.atlas=="Crosshair_attack_32" and row.name=="Kobold Miner" and math.abs(row.x-0.1125)<1e-9)
        assert(Texts(row)=="[28] Quest 40|Kobold Miner slain: 0/8|[28] Quest 42|Kobold Candle: 0/8|Kobold Miner, Kobold Tunneler",
            Texts(row))
    ''',
    "one quest's objectives at a spot share its title, and a tooltip keeps whole sections within 16 lines": '''
        Quests[610]={questLevel=28,objectives={{{50,nil,0}},nil,{{70,nil,0}}}}
        Accept(610,{Goal("Kobold Miner slain: 0/8","monster"),Goal("Kobold Candle: 0/8","item")})
        for quest=1,9 do
            Quests[620+quest]={questLevel=28,objectives={{{50,nil,0}}}}; Accept(620+quest,{Goal("Miner "..quest,"monster")})
        end
        Drain()
        local row=Pick(Collect(3),"objective:610:1:164")[1]
        assert(#row.lines==16, #row.lines)
        assert(Texts(row):find("[28] Quest 610|Kobold Miner slain: 0/8|Kobold Candle: 0/8|Kobold Miner, Kobold Tunneler|[28] Quest 621",1,true),
            Texts(row))
        assert(row.lines[15].text=="[28] Quest 626" and row.lines[16].text=="Miner 6", row.lines[16].text)
    ''',
    "Quest Objectives gates the log's rows and tells the host when it changes": '''
        local calls=Host()
        Accept(40,{Goal("Kobold Miner slain: 0/8","monster")}); Accept(47,{}); Drain()
        local rows=Collect(3)
        assert(#Pick(rows,"objective:")==2 and #Pick(rows,"turnin:")==1 and #Pick(rows,"giver:")==2)
        local provided,refresh=calls.provider.Collect(3)
        assert(#Pick(provided,"objective:")==2 and #Pick(provided,"turnin:")==1 and refresh==60, "the host got no log rows")
        local before=calls.invalidate
        P:SetCompassPointVisibility("ShowQuestObjectives","world",false); P:CacheCompassPointVisibility()
        assert(calls.invalidate>before, "hiding Quest Objectives left the host's rows stale")
        rows=Collect(3)
        assert(#Pick(rows,"objective:")==0 and #Pick(rows,"turnin:")==0 and #Pick(rows,"giver:")==2)
        P:SetCompassPointVisibility("ShowQuestObjectives","world",true)
        P:SetCompassPointVisibility("ShowQuestOffers","world",false); P:CacheCompassPointVisibility()
        rows=Collect(3)
        assert(#Pick(rows,"objective:")==2 and #Pick(rows,"turnin:")==1 and #Pick(rows,"giver:")==0)
    ''',
    "a burst of quest-log events reads the log once and refreshes the host only when it changed": '''
        local calls=Host()
        Accept(40,{Goal("Kobold Miner slain: 0/8","monster")}); Drain(); Collect(3)
        local invalidations,reads=calls.invalidate,mock.logReads
        for _=1,20 do P:InvalidateCompassSource("QUEST_LOG_UPDATE") end
        assert(#mock.timers==1 and calls.invalidate==invalidations and mock.logReads==reads, "a burst acted per event")
        Advance(0.25)
        assert(mock.logReads==reads+1 and calls.invalidate==invalidations, "an unchanged log refreshed the host")
        mock.objectives[40][1].text="Kobold Miner slain: 1/8"
        for _=1,20 do P:InvalidateCompassSource("QUEST_LOG_UPDATE") end
        Advance(0.1); assert(calls.invalidate==invalidations, "refreshed before the burst settled")
        Advance(0.2)
        assert(calls.invalidate==invalidations+1 and mock.logReads==reads+2, "progress did not refresh the host once")
        reads=mock.logReads
        assert(Texts(Pick(Collect(3),"objective:40:1:164")[1])=="[28] Quest 40|Kobold Miner slain: 1/8")
        assert(mock.logReads==reads, "the collection read the log the burst had just read")
        mock.complete[40]=true; P:InvalidateCompassSource("QUEST_LOG_UPDATE"); Advance(0.25)
        assert(calls.invalidate==invalidations+2 and RowKeys(Collect(3),"turnin:")=="turnin:n1:820")
    ''',
    "accepting or abandoning a quest refreshes at once, without waiting for a burst": '''
        local calls=Host()
        Accept(40,{Goal("Kobold Miner slain: 0/8","monster")}); Drain(); Collect(3)
        Accept(41,{Goal("Ore Crate opened: 0/1","object")})
        local before=calls.invalidate
        P:InvalidateCompassSource("QUEST_ACCEPTED")
        assert(calls.invalidate==before+1 and #mock.timers==0)
        assert(#Pick(Collect(3),"objective:41:1:")==1, "an accepted quest waited for the backstop")
        table.remove(mock.entries); mock.log[41]=nil
        P:InvalidateCompassSource("QUEST_REMOVED")
        assert(#Pick(Collect(3),"objective:41:1:")==0, "an abandoned quest kept its icons")
    ''',
    "a client pin keeps a hinted quest's objective icons and takes over its matching turn-in, and a moved pin re-checks it": '''
        local calls=Host()
        Accept(40,{Goal("Kobold Miner slain: 0/8","monster")}); Drain()
        assert(#Pick(Collect(3),"objective:40:1:")==2, "a hinted quest drew no objective icons")
        local before=calls.invalidate
        mock.pins[3]={{questID=40,numObjectives=1,mapID=3,x=0.5,y=0.5,isQuestStart=false,isMapIndicatorQuest=false}}
        P:InvalidateCompassSource("QUEST_POI_UPDATE"); Advance(0.25)
        assert(calls.invalidate==before+1, "a new client pin left the map rows as they were")
        assert(#Pick(Collect(3),"objective:40:1:")==2, "the client's pin took a hint the player asked for")
        mock.pins[3]=nil
        mock.complete[40]=true; P:InvalidateCompassSource("QUEST_LOG_UPDATE"); Advance(0.25)
        assert(calls.invalidate==before+2 and #Pick(Collect(3),"turnin:")==1)
        mock.pins[3]={{questID=40,numObjectives=0,mapID=3,x=0.5,y=0.5,isQuestStart=false,isMapIndicatorQuest=false}}
        P:InvalidateCompassSource("QUEST_POI_UPDATE"); Advance(0.25)
        assert(calls.invalidate==before+3 and #Pick(Collect(3),"turnin:")==0, "the client's late pin left a double")
    ''',
    "a row's menu removes a quest from the map with its giver and turn-in, and restores them": '''
        local calls=Host(); HostStore()
        local L=Addon.L
        mock.done[11]=true
        Accept(40,{Goal("Kobold Miner slain: 0/8","monster")}); Accept(47,{}); Drain()
        local rows=Collect(3)
        local giver=Pick(rows,"giver:npc:1:1")[1]
        assert(giver.menu==L.PLU_COMPASS_MAP_REMOVE, "a giver row offers no right-click")
        assert(Pick(rows,"turnin:")[1].menu==L.PLU_COMPASS_MAP_REMOVE, "a turn-in row offers no right-click")
        local menu=RowMenu(calls.provider,giver.key)
        assert(menu.title==L.PLU_COMPASS_MAP_REMOVE and #menu.rows==1 and not menu.divided)
        assert(menu.rows[1].text:find("Quest 10",1,true), menu.rows[1].text)
        local before=calls.invalidate
        menu.rows[1].run()
        assert(calls.invalidate>before, "a removal left the host's rows stale")
        assert(P.store.QuestieRemovedQuests[10]==true, "a removal was not saved with the character")
        Drain(); rows=Collect(3)
        assert(#Pick(rows,"giver:npc:1:1")==0 and not Available(10), "a removed quest kept its giver")
        menu=RowMenu(calls.provider,Pick(rows,"turnin:")[1].key)
        assert(#menu.rows==2 and menu.rows[1].text=="[28] Quest 47" and menu.divided, menu.rows[1].text)
        assert(menu.rows[2].text==L.PLU_COMPASS_MAP_RESTORE_F:format(1), menu.rows[2].text)
        menu.rows[1].run(); rows=Collect(3)
        assert(#Pick(rows,"turnin:")==0, "a removed quest kept its turn-in")
        assert(#Pick(rows,"objective:")==2, "removing another quest took a hint the player asked for")
        P.compassQuestieHidden=nil
        assert(not Available(10), "a removal did not survive into the next session")
        menu=RowMenu(calls.provider,giver.key)
        assert(#menu.rows==1 and menu.rows[1].text==L.PLU_COMPASS_MAP_RESTORE_F:format(2), menu.rows[1].text)
        menu.rows[1].run()
        assert(P.store.QuestieRemovedQuests==nil, "restoring left the saved list behind")
        Drain(); rows=Collect(3)
        assert(#Pick(rows,"giver:npc:1:1")==1 and #Pick(rows,"objective:")==2 and #Pick(rows,"turnin:")==1,
            "restored quests did not come back")
    ''',
    "objective icons wait for a quest's hint, which a right-click on the quest shows and hides": '''
        local calls=Host(); HostStore()
        local L=Addon.L
        Take(40,{Goal("Kobold Miner slain: 0/8","monster")}); Take(47,{}); Take(999,{Goal("Unknown: 0/1","monster")})
        mock.pins[3]={{questID=40,numObjectives=1,mapID=3,x=0.5,y=0.5,isQuestStart=false,isMapIndicatorQuest=false}}
        Drain()
        local provider=calls.provider
        assert(provider.QuestHint(40)==nil, "a hint was offered before QuestieDB's plan for the quest was read")
        local rows=Collect(3)
        assert(#Pick(rows,"objective:")==0 and #Pick(rows,"turnin:")==1, "an objective icon drew without its hint")
        assert(provider.QuestHint(40)==L.PLU_COMPASS_MAP_HINT_SHOW, "a quest QuestieDB places offered no hint")
        assert(provider.QuestHint(47)==nil and provider.QuestHint(999)==nil and provider.QuestHint(12345)==nil,
            "a quest QuestieDB adds nothing to offered a hint")
        assert(#QuestMenu(provider,47).rows==0, "a quest with no hint took a menu entry")
        local menu=QuestMenu(provider,40)
        assert(#menu.rows==1 and menu.rows[1].text==L.PLU_COMPASS_MAP_HINT_SHOW and not menu.title and not menu.divided)
        local before=calls.invalidate
        menu.rows[1].run()
        assert(calls.invalidate>before, "showing a hint left the host's rows stale")
        assert(P.store.QuestieHintQuests[40]==true, "a hint was not saved with the character")
        rows=Collect(3)
        assert(RowKeys(rows,"objective:")=="objective:40:1:164,objective:40:1:492", RowKeys(rows,"objective:"))
        assert(Pick(rows,"objective:")[1].menu==L.PLU_COMPASS_MAP_HINT_HIDE, "a hint icon does not name its right-click")
        assert(provider.QuestHint(40)==L.PLU_COMPASS_MAP_HINT_HIDE)
        P.compassQuestieHints=nil
        assert(#Pick(Collect(3),"objective:")==2, "a hint did not survive into the next session")
        menu=RowMenu(provider,Pick(rows,"objective:")[1].key)
        assert(menu.title==L.PLU_COMPASS_MAP_HINT_HIDE and #menu.rows==1 and menu.rows[1].text=="[28] Quest 40")
        assert(not menu.divided, "a hint icon's menu offered to restore removed quests")
        menu.rows[1].run()
        assert(P.store.QuestieHintQuests==nil and #Pick(Collect(3),"objective:")==0, "a hidden hint kept its icons")
        QuestMenu(provider,40).rows[1].run()
        assert(#Pick(Collect(3),"objective:")==2, "the quest's own right-click did not show the hint again")
        menu=QuestMenu(provider,40)
        assert(menu.rows[1].text==L.PLU_COMPASS_MAP_HINT_HIDE)
        menu.rows[1].run()
        assert(#Pick(Collect(3),"objective:")==0, "the quest's own right-click did not hide the hint")
        mock.objectives[40][1].finished=true; P:InvalidateCompassSource("QUEST_LOG_UPDATE"); Advance(0.25)
        assert(provider.QuestHint(40)==nil, "a quest with nothing left to find offered a hint")
        mock.objectives[40][1].finished=false; P:InvalidateCompassSource("QUEST_LOG_UPDATE"); Advance(0.25)
        P:SetCompassPointVisibility("ShowQuestObjectives","world",false); P:CacheCompassPointVisibility()
        assert(provider.QuestHint(40)==nil, "a hidden Quest Objectives point still offered hints")
    ''',
    "a quest the client marks nowhere on the map keeps one icon, whose right-click shows its hint": '''
        local calls=Host(); HostStore()
        local L=Addon.L
        Take(45,{Goal("Kobold Miner slain: 0/8","monster"),Goal("Kobold Candle: 0/8","item")}); Drain()
        local rows=Collect(3)
        assert(RowKeys(rows,"objective:")=="objective:45:1:164", "one icon does not stand for the quest: "..RowKeys(rows,"objective:"))
        local icon=Pick(rows,"objective:")[1]
        assert(icon.menu==L.PLU_COMPASS_MAP_HINT_SHOW and icon.scale==0.6, "the icon does not offer the hint")
        assert(Texts(icon)=="[28] Quest 45|Kobold Miner slain: 0/8", Texts(icon))
        local menu=RowMenu(calls.provider,icon.key)
        assert(menu.title==L.PLU_COMPASS_MAP_HINT_SHOW and #menu.rows==1 and menu.rows[1].text=="[28] Quest 45"
            and not menu.divided, "the icon's menu does not show the quest's hint")
        menu.rows[1].run(); rows=Collect(3)
        assert(#Pick(rows,"objective:45:1:")==2 and #Pick(rows,"objective:45:2:")>0, "the hint did not show every spot")
        assert(Pick(rows,"objective:")[1].menu==L.PLU_COMPASS_MAP_HINT_HIDE)
        RowMenu(calls.provider,Pick(rows,"objective:")[1].key).rows[1].run()
        assert(RowKeys(Collect(3),"objective:")=="objective:45:1:164", "hiding the hint left no icon to show it again")
        -- The first objective done, the next one stands for the quest; with the client's own pin, nothing does.
        mock.objectives[45][1].finished=true; P:InvalidateCompassSource("QUEST_LOG_UPDATE"); Advance(0.25)
        rows=Pick(Collect(3),"objective:")
        assert(#rows==1 and rows[1].key:find("objective:45:2:",1,true)==1, "a finished objective still stood for the quest")
        mock.pins[3]={{questID=45,numObjectives=1,mapID=3,x=0.5,y=0.5,isQuestStart=false,isMapIndicatorQuest=false}}
        P:InvalidateCompassSource("QUEST_POI_UPDATE"); Advance(0.25)
        assert(#Pick(Collect(3),"objective:")==0, "a quest with the client's pin kept a stand-in icon")
    ''',
    "a quest an item starts shows one icon where the item drops, and its hint shows every spot": '''
        local calls=Host(); HostStore()
        local L=Addon.L
        Items[72]={name="Torn Note",npcDrops={50,51},questStarts={48}}; Quests[48]={questLevel=28}
        Items[73]={name="Old Map",npcDrops={50},questStarts={49}}; Quests[49]={questLevel=12}
        Drain()
        local first=P:CollectCompassQuestieMapRows(3)
        assert(#Pick(first,"start:")==0 and #Pick(first,"giver:")==2, "givers waited for a dropped item's places")
        local rows=Collect(3)
        assert(RowKeys(rows,"start:")=="start:48:1:164", RowKeys(rows,"start:"))
        assert(mock.reads.npcDrops73==nil, "a quest the character cannot take had its item read")
        assert(mock.reads.quest48==2 and mock.reads.quest49==1, "a quest out of the level range was decoded")
        local row=Pick(rows,"start:")[1]
        assert(row.atlas=="QuestNormal" and row.scale==0.75 and row.name=="Torn Note", row.name)
        assert(row.menu==L.PLU_COMPASS_MAP_HINT_SHOW, "the icon does not offer the hint")
        assert(Texts(row)=="[28] Quest 48|Kobold Miner, Kobold Tunneler", Texts(row))
        local menu=RowMenu(calls.provider,row.key)
        assert(#menu.rows==2 and menu.rows[1].text=="[28] Quest 48" and menu.rows[2].text=="[28] Quest 48" and menu.divided,
            "the icon's menu does not offer the hint and the removal")
        menu.rows[1].run(); rows=Collect(3)
        assert(RowKeys(rows,"start:")=="start:48:1:1312,start:48:1:164,start:48:1:492", RowKeys(rows,"start:"))
        assert(Pick(rows,"start:")[1].menu==L.PLU_COMPASS_MAP_HINT_HIDE)
        assert(RowKeys(Collect(5),"start:")=="start:48:1:656", "another map lost the item's spots there")
        RowMenu(calls.provider,Pick(rows,"start:")[1].key).rows[1].run()
        rows=Collect(3)
        assert(RowKeys(rows,"start:")=="start:48:1:164", "hiding the hint left no icon to show it again")
        RowMenu(calls.provider,Pick(rows,"start:")[1].key).rows[2].run()
        Drain()
        assert(#Pick(Collect(3),"start:")==0 and not Available(48), "a removed quest kept its drop icon")
        P.compassQuestieHidden=nil; P.store.QuestieRemovedQuests=nil
        assert(#Pick(Collect(3),"start:")==1, "the quest did not come back")
        Take(48,{}); P:InvalidateCompassSource("QUEST_ACCEPTED")
        assert(#Pick(Collect(3),"start:")==0, "a quest already taken still marked where its item drops")
    ''',
    "showing a hint drops the hints of quests completed since": '''
        local calls=Host(); HostStore()
        Take(40,{Goal("Kobold Miner slain: 0/8","monster")}); Take(41,{Goal("Ore Crate opened: 0/1","object")}); Drain()
        mock.pins[3]={{questID=40,numObjectives=1,mapID=3,x=0.5,y=0.5,isQuestStart=false,isMapIndicatorQuest=false},
            {questID=41,numObjectives=1,mapID=3,x=0.4,y=0.4,isQuestStart=false,isMapIndicatorQuest=false}}
        Collect(3)
        QuestMenu(calls.provider,41).rows[1].run()
        assert(P.store.QuestieHintQuests[41]==true)
        mock.done[41]=true
        assert(P.store.QuestieHintQuests[41]==true, "a completed quest's hint left before the list was next saved")
        QuestMenu(calls.provider,40).rows[1].run()
        assert(P.store.QuestieHintQuests[40]==true and P.store.QuestieHintQuests[41]==nil, "a completed quest kept its hint")
    ''',
    "without a host store a removal lasts the session and nothing is written": '''
        local calls=Host()
        mock.done[11]=true; Drain()
        local giver=Pick(Collect(3),"giver:npc:1:1")[1]
        RowMenu(calls.provider,giver.key).rows[1].run()
        Drain(); assert(#Pick(Collect(3),"giver:npc:1:1")==0 and not Available(10))
    ''',
    "a quest draws only once the game confirms it exists, and never when the game denies it": '''
        local calls=Host()
        local cached,requests={},{}
        C_QuestLog.GetTitleForQuestID=function(id) return cached[id] and "Quest "..id or nil end
        C_QuestLog.RequestLoadQuestByID=function(id) requests[#requests+1]=id end
        assert(not Available(10) and not Available(14), "an unconfirmed quest was offered")
        Advance(0.1)
        table.sort(requests)
        assert(table.concat(requests,",")=="10,14", "each unconfirmed quest was not asked for once: "..table.concat(requests,","))
        assert(not Available(10)); Advance(0.1); assert(#requests==2, "a quest was asked for twice")
        local before=calls.invalidate
        P:NoteCompassQuestExistence(10,true); P:NoteCompassQuestExistence(14,false); P:NoteCompassQuestExistence(99,true)
        Advance(0.25)
        assert(calls.invalidate==before+1, "the answers did not refresh the map once")
        assert(Available(10) and not Available(14), "the game's answer was not followed")
        cached[18]=true; assert(Available(18) and #requests==2, "a quest the client already holds was asked for")
    ''',
    "a client that confirms no quest at all hides none": '''
        Host()
        C_QuestLog.GetTitleForQuestID=function() return nil end
        C_QuestLog.RequestLoadQuestByID=function() end
        assert(not Available(10), "an unanswered quest was offered at once")
        P:NoteCompassQuestExistence(10,false)
        Advance(5)
        assert(Available(10) and Available(14), "denials were trusted from a client that confirmed nothing")
    ''',
    "a quest whose title carries a retired marker is never offered": '''
        Host()
        local name=LibQuestieDB.Quest.name
        LibQuestieDB.Quest.name=function(id) return id==10 and "<UNUSED> Old errand" or name(id) end
        assert(not Available(10) and Available(14), "a retired quest row was offered")
        LibQuestieDB.Quest.name=name
    ''',
    "the log is read again at the backstop, and bursts stop reading it once no map collects": '''
        Host(); Accept(40,{Goal("Kobold Miner slain: 0/8","monster")}); Drain(); Collect(3)
        local reads=mock.logReads
        mock.now=mock.now+29; Collect(3); assert(mock.logReads==reads, "a fresh snapshot was read again")
        mock.now=mock.now+2; Collect(3); assert(mock.logReads==reads+1, "the backstop reused an old snapshot")
        mock.now=mock.now+91
        for _=1,20 do P:InvalidateCompassSource("QUEST_LOG_UPDATE") end
        assert(#mock.timers==0 and mock.logReads==reads+1, "an unwatched log was still read")
        Collect(3); assert(mock.logReads==reads+2, "the first collection after idling reused a stale snapshot")
        P:SetCompassPointVisibility("ShowQuestObjectives","world",false); P:CacheCompassPointVisibility()
        P:InvalidateCompassSource("QUEST_LOG_UPDATE"); assert(#mock.timers==0, "a hidden point still coalesced bursts")
    ''',
    "a collection reads no QuestieDB table, and preparation keeps to its frame budget": '''
        local calls=Host()
        Accept(40,{Goal("Kobold Miner slain: 0/8","monster")}); Accept(42,{Goal("Kobold Candle: 0/8","item")}); Drain()
        local clock=0; debugprofilestop=function() clock=clock+0.2 return clock end
        mock.reads={}
        local first=P:CollectCompassQuestieMapRows(3)
        assert(#Pick(first,"objective:")==0 and #Pick(first,"giver:")==2, "givers waited for objective data")
        assert(next(mock.reads)==nil, "a collection read a QuestieDB table")
        local before=calls.invalidate
        local frames=Prepare()
        assert(frames>2, frames)
        assert(calls.invalidate==before+1, "preparation asked the host to collect more than once")
        local reads=mock.reads.spawns
        assert(#Pick(P:CollectCompassQuestieMapRows(3),"objective:")==4 and mock.reads.spawns==reads)
        Collect(5); Collect(3); Collect(5)
        assert(mock.reads.spawns50==1 and mock.reads.spawns51==1 and mock.reads.spawns60==1 and mock.reads.spawns1==1)
        assert(mock.reads.quest40==1 and mock.reads.quest42==1 and mock.reads.npcDrops70==1 and mock.reads.vendors==nil)
        local settled=calls.invalidate
        P:CollectCompassQuestieMapRows(99)
        assert(Prepare()>0 and calls.invalidate==settled, "a map the log has no place on asked for another collection")
    ''',
    "quests whose data fails are dropped and reported once while the others still show": '''
        mock.broken={spawns51=true}
        local reports=0; function geterrorhandler() return function() reports=reports+1 end end
        Accept(41,{Goal("Ore Crate opened: 0/1","object")}); Accept(42,{Goal("Kobold Candle: 0/8","item")})
        Accept(43,{Goal("Kobolds slain: 0/10","monster")}); Drain()
        local rows=Collect(3)
        assert(reports==1, reports)
        assert(#Pick(rows,"objective:42:")==0 and #Pick(rows,"objective:43:")==0 and #Pick(rows,"objective:41:1:")==1)
        assert(#Pick(Collect(3),"objective:")==1 and Prepare()==0 and reports==1, "the failed quests were retried")
    ''',
    "a quest QuestieDB does not know contributes nothing and is asked for once": '''
        Accept(999,{Goal("Unknown: 0/1","monster")}); Accept(40,{Goal("Kobold Miner slain: 0/8","monster")}); Drain()
        assert(RowKeys(Collect(3),"objective:")=="objective:40:1:164,objective:40:1:492")
        P:CollectCompassQuestieMapRows(3); assert(Prepare()==0, "an unknown quest was prepared again")
    ''',
    "disabling pauses preparation and forgets the log; the next collection resumes both": '''
        Accept(40,{Goal("Kobold Miner slain: 0/8","monster")}); Drain(); P:CollectCompassQuestieMapRows(3)
        Addon.CompassQuestieObjectives.Stop(P); Addon.CompassQuestieLog.Forget(P)
        assert(Prepare()==0 and P.compassQuestieLog==nil)
        P:InvalidateCompassSource("QUEST_LOG_UPDATE"); assert(#mock.timers==0)
        assert(#Pick(Collect(3),"objective:")==2)
    ''',
    "QuestieDB absent, older or without item reads publishes nothing and reads no log": '''
        Accept(40,{Goal("Kobold Miner slain: 0/8","monster")})
        mock.contract=3; Drain()
        assert(#P:CollectCompassQuestieMapRows(3)==0, "an older contract published rows")
        mock.contract=nil
        local item=LibQuestieDB.Item; LibQuestieDB.Item=nil
        assert(#P:CollectCompassQuestieMapRows(3)==0, "a provider without item reads published rows")
        LibQuestieDB.Item=item
        local lib=LibQuestieDB; LibQuestieDB=nil
        assert(#P:CollectCompassQuestieMapRows(3)==0 and Prepare()==0, "an absent provider published rows")
        assert((mock.logReads or 0)==0, "the log was read without a provider")
        LibQuestieDB=lib
        assert(P:CollectCompassQuestieMapRows(3)==nil, "the index did not start building"); Drain()
        assert(#Pick(Collect(3),"objective:")==2, "a compatible provider stayed silent")
    ''',
}

RETAIL = '''
    for _,tab in ipairs(Addon.SettingsTabs(1)) do
        for _,control in ipairs(tab.controls) do assert(control.key~="QuestLevelRange", "Retail renders the slider") end
    end
    Drain()
    assert(P.compassSources.questie.status=="unsupported" and Keys()=="")
    assert(not Addon.ClientFeatures.AllowsPoint("ShowServices"))
    local calls=Host()
    assert(calls.register==0, "Retail registered the map point provider")
    Accept(40,{Goal("Kobold Miner slain: 0/8","monster")})
    P:InvalidateCompassSource("QUEST_LOG_UPDATE"); P:InvalidateCompassSource("QUEST_ACCEPTED")
    assert(#mock.timers==0 and (mock.logReads or 0)==0 and calls.invalidate==0, "Retail read the log for QuestieDB")
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
