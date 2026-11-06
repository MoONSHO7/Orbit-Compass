local _, Addon = ...
local L = Addon.L
local C = Addon.Constants
local Readable = Addon.SourceUtils.Readable
local Fold, Words = Addon.Text.Fold, Addon.Text.Words
local ALIAS_ENTRY = "[^;]+"
local ALIAS_ASSIGNMENT = "^ *([A-Za-z]+) *=(.*)$"
local ALIAS_LIST_SEPARATOR = "[^,]+"
local CATEGORY_KINDS = {
    dungeon = { "dungeon" },
    raid = { "raid" },
    instance = { "dungeon", "raid", "instance" },
    delve = { "delve" },
    flightMaster = { "flightMaster" },
    mapLink = { "mapLink", "teleport" },
    teleport = { "teleport" },
    cave = { "cave" },
    zone = { "zone", "city" },
    city = { "city" },
    continent = { "continent" },
    area = { "area" },
    event = { "event" },
    race = { "race" },
    questHub = { "questHub" },
    petTamer = { "petTamer" },
    poi = { "poi" },
    saved = { "saved" },
    digSite = { "digSite" },
    worldQuest = { "worldQuest", "worldBoss" },
    worldBoss = { "worldBoss" },
    bonusObjective = { "bonusObjective" },
    quest = { "quest", "worldQuest", "worldBoss", "bonusObjective", "questOffer" },
    questOffer = { "questOffer" },
    rare = { "rare", "rareElite" },
    rareElite = { "rareElite" },
    treasure = { "treasure" },
    invasion = { "invasion" },
    graveyard = { "graveyard" },
    handynotes = { "handynotes" },
}
-- Typed search words, not display text: English aliases work in every locale beside the localized aliases.
local ENGLISH_ALIASES = {
    dungeon = { "dungeon", "dungeons" },
    raid = { "raid", "raids" },
    instance = { "instance", "instances" },
    delve = { "delve", "delves" },
    flightMaster = {
        "flight master",
        "flight masters",
        "flightmaster",
        "flightmasters",
        "flight point",
        "flight points",
        "flight path",
        "flight paths",
        "flights",
        "taxi",
        "fp",
    },
    mapLink = { "portal", "portals", "map link", "map links", "transport", "transports" },
    teleport = { "teleport", "teleports", "teleporter", "teleporters" },
    cave = { "cave", "caves", "tunnel", "tunnels" },
    zone = { "zone", "zones", "region", "regions" },
    city = { "city", "cities", "capital", "capitals", "town", "towns" },
    continent = { "continent", "continents" },
    area = { "area", "areas", "subzone", "subzones" },
    event = { "event", "events" },
    race = {
        "race",
        "races",
        "sky riding",
        "skyriding",
        "skyriding race",
        "skyriding races",
        "dragonriding",
        "dragon riding",
        "dragon race",
        "dragon races",
    },
    questHub = { "quest hub", "quest hubs", "hub", "hubs" },
    petTamer = {
        "pet tamer",
        "pet tamers",
        "pet trainer",
        "pet trainers",
        "pet battle",
        "pet battles",
        "battle pet",
        "battle pets",
        "tamer",
        "tamers",
    },
    poi = { "poi", "pois", "point of interest", "points of interest" },
    saved = { "saved", "saved location", "saved locations" },
    digSite = { "dig site", "dig sites", "digsite", "digsites", "archaeology", "dig", "digs" },
    worldQuest = { "world quest", "world quests", "wq", "wqs" },
    worldBoss = { "world boss", "world bosses" },
    bonusObjective = { "bonus objective", "bonus objectives", "bonus", "bonuses" },
    quest = { "quest", "quests" },
    questOffer = { "available quest", "available quests", "quest giver", "quest givers" },
    rare = { "rare", "rares" },
    rareElite = { "rare elite", "rare elites", "elite", "elites" },
    treasure = { "treasure", "treasures", "chest", "chests" },
    invasion = { "invasion", "invasions" },
    graveyard = { "graveyard", "graveyards", "spirit healer", "spirit healers" },
    handynotes = { "handynotes", "handy notes", "note", "notes" },
}
-- Blizzard's map legend names are localized by the client and name every clickable world-map category.
local LEGEND_CATEGORIES = {
    MAP_LEGEND_DUNGEON = "dungeon",
    MAP_LEGEND_RAID = "raid",
    MAP_LEGEND_HUB = "questHub",
    MAP_LEGEND_DIGSITE = "digSite",
    MAP_LEGEND_PETBATTLE = "petTamer",
    MAP_LEGEND_DELVE = "delve",
    MAP_LEGEND_TELEPORT = "teleport",
    MAP_LEGEND_CAVE = "cave",
    MAP_LEGEND_FLIGHTPOINT = "flightMaster",
    MAP_LEGEND_WORLDQUEST = "worldQuest",
    MAP_LEGEND_WORLDBOSS = "worldBoss",
    MAP_LEGEND_BONUSOBJECTIVE = "bonusObjective",
    MAP_LEGEND_EVENT = "event",
    MAP_LEGEND_RARE = "rare",
    MAP_LEGEND_RAREELITE = "rareElite",
    MAP_LEGEND_LOCALSTORY = "questOffer",
    MAP_LEGEND_CAMPAIGN = "quest",
    MAP_LEGEND_INPROGRESS = "quest",
    MAP_LEGEND_TURNIN = "quest",
}

local Keywords = {}

local function AddKeyword(keywords, seen, word, category)
    word = Readable(word)
    if type(word) ~= "string" then
        return
    end
    local phrase = Fold(word)
    local identity = phrase .. "\0" .. category
    if phrase ~= "" and not seen[identity] then
        seen[identity] = true
        keywords[#keywords + 1] = { phrase = phrase, words = Words(phrase), kinds = CATEGORY_KINDS[category] }
    end
end

function Keywords.Build()
    local keywords, seen = {}, {}
    for category, words in pairs(ENGLISH_ALIASES) do
        for _, word in ipairs(words) do
            AddKeyword(keywords, seen, word, category)
        end
    end
    for category in pairs(CATEGORY_KINDS) do
        local labelKey = C.POINT_TYPE_LABELS[category]
        if labelKey then
            AddKeyword(keywords, seen, L[labelKey], category)
        end
    end
    for globalName, category in pairs(LEGEND_CATEGORIES) do
        AddKeyword(keywords, seen, _G[globalName], category)
    end
    for entry in string.gmatch(L.PLU_COMPASS_SEARCH_ALIASES, ALIAS_ENTRY) do
        local category, words = string.match(entry, ALIAS_ASSIGNMENT)
        if category and CATEGORY_KINDS[category] then
            for word in string.gmatch(words, ALIAS_LIST_SEPARATOR) do
                AddKeyword(keywords, seen, word, category)
            end
        end
    end
    table.sort(keywords, function(a, b)
        if #a.words ~= #b.words then
            return #a.words > #b.words
        end
        if #a.phrase ~= #b.phrase then
            return #a.phrase > #b.phrase
        end
        return a.phrase < b.phrase
    end)
    return keywords
end

Addon.LandmarkKeywords = table.freeze(Keywords)
