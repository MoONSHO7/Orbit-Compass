local _, Addon = ...
local Readable, Number = Addon.SourceUtils.Readable, Addon.SourceUtils.Number
local HasBit = Addon.CompassQuestieIndex.HasBit
-- specialFlags bit 1 marks a repeatable quest; bit 2 is how a quest completes (exploration or event), not availability.
local REPEATABLE_FLAG = 1
-- QuestSort categories whose quests exist only during holidays, as negative zoneOrSort values.
local HOLIDAY_SORTS = {
    [-21] = true,
    [-22] = true,
    [-364] = true,
    [-366] = true,
    [-369] = true,
    [-370] = true,
    [-374] = true,
    [-376] = true,
    [-378] = true,
    [-402] = true,
    [-404] = true,
}
local CLASS_KEYS = { DEATHKNIGHT = "DEATH_KNIGHT", DEMONHUNTER = "DEMON_HUNTER" }
local FIELDS = {
    "requiredLevel",
    "questLevel",
    "requiredRaces",
    "requiredClasses",
    "preQuestGroup",
    "preQuestSingle",
    "exclusiveTo",
    "zoneOrSort",
    "requiredSkill",
    "requiredMinRep",
    "requiredMaxRep",
    "nextQuestInChain",
    "specialFlags",
    "parentQuest",
    "breadcrumbForQuestId",
    "requiredSpell",
    "requiredSpecialization",
    "requiredMaxLevel",
    "availableUntilCompleted",
    "availableStartingWith",
    "requiredRanks",
    "disabledByQuest",
}
local Availability = {}

local function Completed(questID)
    return Readable(C_QuestLog.IsQuestFlaggedCompleted(questID)) == true
end

local function InLog(questID)
    return Number(C_QuestLog.GetLogIndexForQuestID(questID)) ~= nil
end

local function AnyDone(list)
    for _, questID in ipairs(list) do
        if Completed(questID) then
            return true
        end
    end
    return false
end

local function AllDone(list)
    for _, questID in ipairs(list) do
        if not Completed(questID) then
            return false
        end
    end
    return true
end

local function AnyTaken(list)
    for _, questID in ipairs(list) do
        if Completed(questID) or InLog(questID) then
            return true
        end
    end
    return false
end

local function Standing(factionID)
    local data = C_Reputation.GetFactionDataByID(factionID)
    data = Readable(data)
    return type(data) == "table" and Number(data.currentStanding) or 0
end

-- Character facts for one collection; verdicts cache in it until the next one. `quests` is the session's decoded quest
-- data (static), and `levelRange` the Quest Level Range: quests further above or below the character stay hidden.
function Availability.Context(lib, levelRange, quests)
    local _, classFile = UnitClass("player")
    local _, _, raceID = UnitRace("player")
    local faction = Readable(UnitFactionGroup("player"))
    classFile = Readable(classFile)
    return {
        lib = lib,
        quests = quests,
        level = Number(UnitLevel("player")) or 0,
        levelRange = levelRange,
        raceBit = Number(lib.Enum.raceMaskById[Number(raceID)]),
        classBit = type(classFile) == "string" and Number(lib.Enum.classKeys[CLASS_KEYS[classFile] or classFile])
            or nil,
        factionLetter = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil,
        verdicts = {},
        levels = {},
    }
end

local function Requirements(context, quest)
    local level = context.level
    if quest.requiredLevel > level or (quest.requiredMaxLevel > 0 and level > quest.requiredMaxLevel) then
        return false
    end
    if quest.requiredRaces > 0 and not HasBit(quest.requiredRaces, context.raceBit) then
        return false
    end
    if quest.requiredClasses > 0 and not HasBit(quest.requiredClasses, context.classBit) then
        return false
    end
    -- Skill, spell, specialization and rank gates cannot be confirmed here, so those quests stay hidden.
    if quest.requiredSkill or quest.requiredSpell > 0 or quest.requiredSpecialization > 0 or quest.requiredRanks then
        return false
    end
    local minRep, maxRep = quest.requiredMinRep, quest.requiredMaxRep
    if minRep and Standing(minRep[1]) < (Number(minRep[2]) or 0) then
        return false
    end
    if maxRep and Standing(maxRep[1]) >= (Number(maxRep[2]) or 0) then
        return false
    end
    return true
end

local function Chain(quest)
    if quest.preQuestGroup and not AllDone(quest.preQuestGroup) then
        return false
    end
    if quest.preQuestSingle and not AnyDone(quest.preQuestSingle) then
        return false
    end
    if quest.exclusiveTo and AnyTaken(quest.exclusiveTo) then
        return false
    end
    local next, target = quest.nextQuestInChain, quest.breadcrumbForQuestId
    if (next > 0 and (Completed(next) or InLog(next))) or (target > 0 and (Completed(target) or InLog(target))) then
        return false
    end
    if quest.parentQuest > 0 and not InLog(quest.parentQuest) then
        return false
    end
    if quest.availableUntilCompleted > 0 and Completed(quest.availableUntilCompleted) then
        return false
    end
    local startingWith = quest.availableStartingWith
    if startingWith > 0 and not (InLog(startingWith) or Completed(startingWith)) then
        return false
    end
    return not (quest.disabledByQuest > 0 and InLog(quest.disabledByQuest))
end

-- QuestieDB's quest rows never change in a session, so each quest is decoded once; false marks an unknown quest.
local function QuestData(context, questID)
    local quest = context.quests[questID]
    if quest == nil then
        local values = context.lib.Quest.GetAll(questID, FIELDS)
        quest = false
        if type(values) == "table" then
            quest = {}
            for index, field in ipairs(FIELDS) do
                quest[field] = values[index]
            end
        end
        context.quests[questID] = quest
    end
    return quest
end

local function Evaluate(context, questID)
    local quest = QuestData(context, questID)
    if not quest then
        return false
    end
    context.levels[questID] = quest.questLevel > 0 and quest.questLevel or nil
    if HOLIDAY_SORTS[quest.zoneOrSort] then
        return false
    end
    if InLog(questID) or (Completed(questID) and not HasBit(quest.specialFlags, REPEATABLE_FLAG)) then
        return false
    end
    if not Requirements(context, quest) or not Chain(quest) then
        return false
    end
    return quest.questLevel <= 0 or math.abs(context.level - quest.questLevel) <= context.levelRange
end

function Availability.IsAvailable(context, questID)
    questID = Number(questID)
    if not questID then
        return false
    end
    local verdict = context.verdicts[questID]
    if verdict == nil then
        verdict = Evaluate(context, questID)
        context.verdicts[questID] = verdict
    end
    return verdict
end

-- The quest's own level once IsAvailable has evaluated it; nil for unknown or unlevelled quests.
function Availability.Level(context, questID)
    return context.levels[Number(questID)]
end

-- NPC givers and services serve only the factions QuestieDB marks friendly; objects have no such restriction.
function Availability.Serves(context, record)
    local faction = record.faction
    return faction == nil or (context.factionLetter ~= nil and faction:find(context.factionLetter, 1, true) ~= nil)
end

Addon.CompassQuestieAvailability = table.freeze(Availability)
