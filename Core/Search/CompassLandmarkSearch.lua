local _, Addon = ...
local L = Addon.L
local C = Addon.Constants
local Plugin = Addon.Controller
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local Text = Addon.Text
local Fold, Words, AddSearchFields = Text.Fold, Text.Words, Text.AddSearchFields
local MIN_QUERY_LENGTH = 2
local MIN_PARTIAL_LENGTH = 3
local TYPO_MIN_LENGTH = 4
local TYPO_WIDE_LENGTH = 7
local SPACE_BYTE = 32
local WORD_EXACT = 3
local WORD_PREFIX = 2
local WORD_TYPO = 1
local SCORE_EXACT = 1000
local SCORE_PREFIX = 900
local SCORE_WORD_START = 800
local SCORE_SUBSTRING = 700
local SCORE_LENGTH_PENALTY_CAP = 60
local SCORE_NAME_WORDS = 600
local SCORE_MIXED_WORDS = 520
local SCORE_CATEGORY = 500
local SCORE_PLACE_WORDS = 440
local SCORE_EXACT_WORD_BONUS = 10
local SCORE_TYPO_PENALTY = 200
local SCORE_CATEGORY_BONUS = 80
local SCORE_SUBSEQUENCE = 250
local SCORE_SUBSEQUENCE_BONUS_CAP = 90
local SUBSEQUENCE_RUN_BONUS = 5
local SUBSEQUENCE_START_BONUS = 10
local SUBSEQUENCE_LOOSE_LETTERS = 1
local FUZZY_RESULT_THRESHOLD = 12
local TIER_EXACT = 5
local TIER_PREFIX = 4
local TIER_WORD_START = 3
local TIER_SUBSTRING = 2
local TIER_LOOSE = 1
local ALIAS_ENTRY = "[^;]+"
local ALIAS_ASSIGNMENT = "^ *([A-Za-z]+) *=(.*)$"
local ALIAS_LIST_SEPARATOR = "[^,]+"
local QUEST_PROGRESS_ATLAS = "Quest-In-Progress-Icon-yellow"
local QUEST_COMPLETE_ATLAS = "UI-QuestIcon-TurnIn-Normal"
local LIVE_MARKER_EXCLUDED = { route = true, waypoint = true, corpse = true, directions = true }
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
local KIND_ORDER = {
    continent = 1,
    city = 2,
    zone = 3,
    dungeon = 4,
    raid = 4,
    delve = 5,
    mapLink = 6,
    teleport = 6,
    cave = 7,
    flightMaster = 8,
    saved = 9,
    quest = 10,
    worldBoss = 11,
    worldQuest = 12,
    bonusObjective = 13,
    questOffer = 14,
    rareElite = 15,
    rare = 16,
    treasure = 17,
    event = 18,
    race = 19,
    questHub = 20,
    petTamer = 21,
    digSite = 22,
    invasion = 23,
    area = 24,
    graveyard = 25,
    poi = 26,
}
local UNLISTED_KIND_ORDER = 27

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

local function BuildKeywords()
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

local function StartsWith(text, prefix)
    return string.find(text, prefix, 1, true) == 1
end

-- The last word of a phrase may be partial, so "dung" or "flight mas" select a category while typing.
local function PhraseMatches(queryWords, start, phraseWords, consumed)
    for offset, phraseWord in ipairs(phraseWords) do
        local index = start + offset - 1
        local word = queryWords[index]
        if not word or consumed[index] then
            return false
        end
        local last = offset == #phraseWords
        if word ~= phraseWord and not (last and #word >= MIN_PARTIAL_LENGTH and StartsWith(phraseWord, word)) then
            return false
        end
    end
    return true
end

local function ParseQuery(keywords, queryWords)
    local consumed, kinds = {}, nil
    for _, keyword in ipairs(keywords) do
        for start = 1, #queryWords - #keyword.words + 1 do
            if PhraseMatches(queryWords, start, keyword.words, consumed) then
                kinds = kinds or {}
                for _, kind in ipairs(keyword.kinds) do
                    kinds[kind] = true
                end
                for index = start, start + #keyword.words - 1 do
                    consumed[index] = true
                end
                break
            end
        end
    end
    local rest = {}
    for index, word in ipairs(queryWords) do
        if not consumed[index] then
            rest[#rest + 1] = word
        end
    end
    return kinds, rest
end

-- Distance from the typed word to the closest prefix of the target, so a partly typed word with a slip still matches.
local function PrefixDistance(word, target, limit, rows)
    local wordLength = #word
    local columns = math.min(#target, wordLength + limit)
    if columns < wordLength - limit then
        return limit + 1
    end
    local targetBytes, twoBack, previous, current = rows.target, rows.twoBack, rows.previous, rows.current
    for column = 1, columns do
        targetBytes[column] = string.byte(target, column)
    end
    for column = 0, columns do
        previous[column] = column
    end
    for line = 1, wordLength do
        local wordByte = string.byte(word, line)
        local priorWordByte = line > 1 and string.byte(word, line - 1)
        current[0] = line
        local best = line
        for column = 1, columns do
            local targetByte = targetBytes[column]
            local value = previous[column - 1] + (wordByte == targetByte and 0 or 1)
            local deletion, insertion = previous[column] + 1, current[column - 1] + 1
            if deletion < value then
                value = deletion
            end
            if insertion < value then
                value = insertion
            end
            if
                priorWordByte
                and column > 1
                and wordByte == targetBytes[column - 1]
                and priorWordByte == targetByte
                and twoBack[column - 2] + 1 < value
            then
                value = twoBack[column - 2] + 1
            end
            current[column] = value
            if value < best then
                best = value
            end
        end
        if best > limit then
            return limit + 1
        end
        twoBack, previous, current = previous, current, twoBack
    end
    local distance = limit + 1
    for column = math.max(0, wordLength - limit), columns do
        if previous[column] < distance then
            distance = previous[column]
        end
    end
    return distance
end

local function TypoLimit(word)
    if #word < TYPO_MIN_LENGTH then
        return 0
    end
    return #word < TYPO_WIDE_LENGTH and 1 or 2
end

local function IsTypoMatch(word, target, limit, rows)
    local matches = rows.matches[word]
    if not matches then
        matches = {}
        rows.matches[word] = matches
    end
    local match = matches[target]
    if match == nil then
        match = PrefixDistance(word, target, limit, rows) <= limit
        matches[target] = match
    end
    return match
end

-- Returns 3 for a whole word, 2 for a prefix and 1 for a typo; typos are only considered in the fuzzy pass.
local function WordMatch(word, targets, rows)
    local best = nil
    local limit = rows and TypoLimit(word) or 0
    local firstByte = string.byte(word, 1)
    for _, target in ipairs(targets) do
        if target == word then
            return WORD_EXACT
        elseif StartsWith(target, word) then
            best = WORD_PREFIX
        elseif
            not best
            and limit > 0
            and string.byte(target, 1) == firstByte
            and IsTypoMatch(word, target, limit, rows)
        then
            best = WORD_TYPO
        end
    end
    return best
end

local function WordsScore(entry, words, rows)
    local nameHits, placeHits, typos, exact = 0, 0, 0, 0
    for _, word in ipairs(words) do
        local match = WordMatch(word, entry.nameWords, rows)
        if match then
            nameHits = nameHits + 1
        else
            match = WordMatch(word, entry.placeWords, rows)
            if not match then
                return
            end
            placeHits = placeHits + 1
        end
        if match == WORD_TYPO then
            typos = typos + 1
        elseif match == WORD_EXACT then
            exact = exact + 1
        end
    end
    local base = placeHits == 0 and SCORE_NAME_WORDS or (nameHits > 0 and SCORE_MIXED_WORDS or SCORE_PLACE_WORDS)
    local tier = typos > 0 and TIER_LOOSE or (placeHits == 0 and TIER_WORD_START or TIER_SUBSTRING)
    return base + exact * SCORE_EXACT_WORD_BONUS - typos * SCORE_TYPO_PENALTY, tier
end

-- Letters in order across the name, rewarded when they start words or run consecutively.
local function SubsequenceScore(name, letters)
    local letterCount = #letters
    local position, bonus, anchored, previous = 1, 0, 0, nil
    local wanted = string.byte(letters, 1)
    for index = 1, #name do
        if string.byte(name, index) == wanted then
            if previous and index == previous + 1 then
                bonus, anchored = bonus + SUBSEQUENCE_RUN_BONUS, anchored + 1
            elseif index == 1 or string.byte(name, index - 1) == SPACE_BYTE then
                bonus, anchored = bonus + SUBSEQUENCE_START_BONUS, anchored + 1
            end
            previous, position = index, position + 1
            if position > letterCount then
                if anchored < letterCount - SUBSEQUENCE_LOOSE_LETTERS then
                    return
                end
                return SCORE_SUBSEQUENCE + math.min(bonus, SCORE_SUBSEQUENCE_BONUS_CAP)
            end
            wanted = string.byte(letters, position)
        end
    end
end

local function NameScore(entry, query, rows)
    local name = entry.searchText
    if name == query.text then
        return SCORE_EXACT, TIER_EXACT
    end
    local start = string.find(entry.search, query.padded, 1, true)
    local lengthPenalty = math.min(#name - #query.text, SCORE_LENGTH_PENALTY_CAP)
    if start == 1 then
        return SCORE_PREFIX - lengthPenalty, TIER_PREFIX
    elseif start then
        return SCORE_WORD_START - lengthPenalty, TIER_WORD_START
    elseif string.find(name, query.text, 1, true) then
        return SCORE_SUBSTRING - lengthPenalty, TIER_SUBSTRING
    end
    local score, tier = WordsScore(entry, query.words, rows)
    if score then
        return score, tier
    elseif rows and #query.letters >= MIN_PARTIAL_LENGTH then
        local loose = SubsequenceScore(name, query.letters)
        return loose, loose and TIER_LOOSE
    end
end

local function CategoryScore(entry, query, rows)
    if not query.kinds or not query.kinds[entry.kind] then
        return
    elseif #query.rest == 0 then
        return SCORE_CATEGORY, TIER_WORD_START
    end
    local score, tier = WordsScore(entry, query.rest, rows)
    if score then
        return score + SCORE_CATEGORY_BONUS, tier == TIER_LOOSE and TIER_LOOSE or TIER_WORD_START
    end
end

-- Pass nil rows for the strict pass; the fuzzy pass supplies scratch rows and enables typos and loose letters.
local function Score(entry, query, rows)
    local name, nameTier = NameScore(entry, query, rows)
    local category, categoryTier = CategoryScore(entry, query, rows)
    if category and (not name or category > name) then
        return category, categoryTier
    end
    return name, nameTier
end

local function MapName(mapID)
    local info = mapID and Readable(C_Map.GetMapInfo(mapID))
    local name = type(info) == "table" and Readable(info.name)
    return type(name) == "string" and name or nil
end

local function LiveEntry(fields, zone)
    fields.zone = zone
    return AddSearchFields(fields, fields.name, zone)
end

local function SavedLocations(plugin, consider)
    for _, location in pairs(plugin.compassLocations:Records()) do
        local name = type(location) == "table" and Readable(location.name)
        local mapID = type(name) == "string" and Number(location.mapID)
        if mapID and plugin:IsCompassLocationUsable(location) then
            consider(LiveEntry({
                kind = "saved",
                key = "saved:" .. location.id,
                locationID = location.id,
                clientFamily = location.clientFamily,
                name = name,
                mapID = mapID,
                x = location.x,
                y = location.y,
                atlas = C.FALLBACK_ATLAS,
            }, MapName(mapID)))
        end
    end
end

local function QuestLog(plugin, consider, indexed)
    for index = 1, Number(C_QuestLog.GetNumQuestLogEntries()) or 0 do
        local info = Readable(C_QuestLog.GetInfo(index))
        local questID = type(info) == "table" and Number(info.questID)
        local title = questID and Readable(info.title)
        if
            type(title) == "string"
            and title ~= ""
            and Readable(info.isHeader) ~= true
            and Readable(info.isHidden) ~= true
            and Utils.AllowsQuest(questID)
            and not indexed["quest:" .. questID]
        then
            local complete = Readable(C_QuestLog.IsComplete(questID)) == true
            consider(LiveEntry({
                kind = "quest",
                key = "quest:" .. questID,
                questID = questID,
                name = title,
                atlas = complete and QUEST_COMPLETE_ATLAS or QUEST_PROGRESS_ATLAS,
            }))
        end
    end
end

local function CompassMarkers(plugin, consider, indexed)
    local zone = MapName(plugin.mapID)
    for _, marker in ipairs(plugin.markers) do
        if not LIVE_MARKER_EXCLUDED[marker.kind] and not indexed[marker.key] then
            local fields =
                { kind = marker.kind, key = marker.key, name = marker.name, atlas = marker.atlas, marker = marker }
            for _, field in ipairs(C.MARKER_ART_FIELDS) do
                fields[field] = marker[field]
            end
            consider(LiveEntry(fields, zone))
        end
    end
end

function Plugin:NewCompassSearchScratch()
    return { scores = {}, tiers = {} }
end

-- Callers own their scratch so the inline field and an Orbit search session never share score tables.
function Plugin:SearchCompassLandmarks(text, results, scratch, options)
    wipe(results)
    local scores, tiers = scratch.scores, scratch.tiers
    wipe(scores)
    wipe(tiers)
    local fuzzy = not options or options.fuzzy ~= false
    local folded = Fold(text)
    if strlenutf8(folded) < MIN_QUERY_LENGTH then
        return results
    end
    local profiler = Addon.Services.profiler
    local start, startKB
    if profiler then
        start, startKB = profiler:Begin()
    end
    self.compassSearchKeywords = self.compassSearchKeywords or BuildKeywords()
    self.compassSearchRows = self.compassSearchRows or { target = {}, twoBack = {}, previous = {}, current = {} }
    local words = Words(folded)
    local kinds, rest = ParseQuery(self.compassSearchKeywords, words)
    local query = {
        text = folded,
        padded = " " .. folded,
        words = words,
        letters = (string.gsub(folded, " ", "")),
        kinds = kinds,
        rest = rest,
    }
    local live = {}
    local function Collect(entry)
        if Addon.ClientFeatures.AllowsKind(entry.kind) then
            live[#live + 1] = entry
        end
    end
    local indexed = self.compassLandmarks.positions
    if Addon.ClientFeatures.quests then
        QuestLog(self, Collect, indexed)
    end
    CompassMarkers(self, Collect, indexed)
    SavedLocations(self, Collect)
    local landmarks = self:GetCompassLandmarks()
    local function Pass(rows)
        for _, group in ipairs({ landmarks, live }) do
            for _, entry in ipairs(group) do
                if Addon.ClientFeatures.AllowsKind(entry.kind) and not scores[entry] then
                    local score, tier = Score(entry, query, rows)
                    if score then
                        results[#results + 1] = entry
                        scores[entry], tiers[entry] = score, tier
                    end
                end
            end
        end
    end
    Pass(nil)
    if fuzzy and #results < FUZZY_RESULT_THRESHOLD then
        self.compassSearchRows.matches = {}
        Pass(self.compassSearchRows)
        self.compassSearchRows.matches = nil
    end
    table.sort(results, function(a, b)
        if scores[a] ~= scores[b] then
            return scores[a] > scores[b]
        end
        local kindA, kindB = KIND_ORDER[a.kind] or UNLISTED_KIND_ORDER, KIND_ORDER[b.kind] or UNLISTED_KIND_ORDER
        if kindA ~= kindB then
            return kindA < kindB
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return (a.zone or "") < (b.zone or "")
    end)
    local limit = options and options.limit
    if limit then
        for index = #results, limit + 1, -1 do
            results[index] = nil
        end
    end
    if start then
        profiler:End(self, "Compass.Search.Query", start, startKB)
    end
    return results
end

function Plugin:ChooseCompassSearchResult(result)
    if not self:IsActive() or self:IsProfileSuppressed() or not Addon.ClientFeatures.AllowsKind(result.kind) then
        return false, L.CMD_COMPASS_UNAVAILABLE
    end
    if result.indexed then
        local index = self.compassLandmarks.positions[result.key]
        if self.compassLandmarks.entries[index] ~= result then
            return false, L.CMD_COMPASS_UNAVAILABLE
        end
    end
    local marker = result.marker
    if marker then
        local current = false
        for _, candidate in ipairs(self.markers) do
            if candidate == marker then
                current = true
                break
            end
        end
        if not current then
            return false, L.CMD_COMPASS_UNAVAILABLE
        end
        local destination = marker.destination
        return self:SetWaypoint(
            destination.mapID,
            destination.x,
            destination.y,
            marker.name,
            marker.description,
            marker.sourceKey or marker.key,
            marker.handynotesPoint
        )
    elseif result.kind == "saved" then
        local location = self.compassLocations:Get(result.locationID)
        if
            not self:IsCompassLocationUsable(location)
            or location.mapID ~= result.mapID
            or location.x ~= result.x
            or location.y ~= result.y
            or location.clientFamily ~= result.clientFamily
        then
            return false, L.CMD_COMPASS_LOCATION_CLIENT
        end
        return self:SetWaypoint(location.mapID, location.x, location.y, location.name)
    end
    return self:TrackCompassLandmark(result)
end
