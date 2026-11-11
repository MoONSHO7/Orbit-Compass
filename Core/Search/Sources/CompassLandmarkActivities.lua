local _, Addon = ...
local F = Addon.ClientFeatures
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local Record = Addon.LandmarkRecord
local Landmark = Record.New
local PIN_KEYS = Record.PinKeys
local QUEST_KEY = Record.QuestKey
local ReadList = Addon.LandmarkRead.List

local DIG_SITE = Enum.SuperTrackingMapPinType.DigSite
local DIG_SITE_ATLAS = "ArchBlob"
local INVASION_KEY = "invasion:"
local WORLD_QUEST_ATLAS = "worldquest-icon"
local WORLD_BOSS_ATLAS = "vignettekillboss"
local BONUS_OBJECTIVE_ATLAS = "Bonus-Objective-Star"

local function CollectDigSites(mapID, place, depth, add, checkpoint, wins)
    if not F.digSites then
        return
    end
    for _, info in ipairs(ReadList(C_ResearchInfo.GetDigSitesForMap(mapID), checkpoint)) do
        info = Readable(info)
        local id = type(info) == "table" and Number(info.researchSiteID)
        local key = PIN_KEYS[DIG_SITE]
        if id and wins(key, id, depth) then
            add(Landmark(key, DIG_SITE, id, mapID, info.position, info.name, DIG_SITE_ATLAS, "digSite", place), depth)
        end
        checkpoint()
    end
end

local function CollectTaskQuests(mapID, place, depth, add, checkpoint, wins)
    if not F.tasks then
        return
    end
    for _, info in ipairs(ReadList(C_TaskQuest.GetQuestsOnMap(mapID), checkpoint)) do
        info = Readable(info)
        local questID = type(info) == "table" and Number(info.questID)
        local rank = questID and depth - (Number(info.childDepth) or 0)
        if questID and Readable(info.isMapIndicatorQuest) ~= true and wins(QUEST_KEY, questID, rank) then
            local title = Readable(C_TaskQuest.GetQuestInfoByQuestID(questID))
            local kind, atlas = "bonusObjective", BONUS_OBJECTIVE_ATLAS
            if Number(info.questTagType) == Enum.QuestTagType.WorldBoss then
                kind, atlas = "worldBoss", WORLD_BOSS_ATLAS
            elseif Readable(C_QuestLog.IsWorldQuest(questID)) == true then
                kind, atlas = "worldQuest", WORLD_QUEST_ATLAS
            end
            local position = { x = info.x, y = info.y }
            add(Landmark(QUEST_KEY, nil, questID, mapID, position, title, atlas, kind, place), rank)
        end
        checkpoint()
    end
end

local function CollectInvasion(mapID, place, depth, add, checkpoint, wins)
    if not F.invasions then
        return
    end
    local id = Number(C_InvasionInfo.GetInvasionForUiMapID(mapID))
    checkpoint()
    local info = id and wins(INVASION_KEY, id, depth) and Readable(C_InvasionInfo.GetInvasionInfo(id))
    if type(info) == "table" then
        add(Landmark(INVASION_KEY, nil, id, mapID, info.position, info.name, info.atlasName, "invasion", place), depth)
    end
end

Addon.LandmarkActivities = table.freeze({
    CollectDigSites = CollectDigSites,
    CollectTaskQuests = CollectTaskQuests,
    CollectInvasion = CollectInvasion,
})
