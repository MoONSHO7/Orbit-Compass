local _, Addon = ...
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
local TIER_EXACT = 5
local TIER_PREFIX = 4
local TIER_WORD_START = 3
local TIER_SUBSTRING = 2
local TIER_LOOSE = 1
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

local Rank = { MIN_PARTIAL_LENGTH = MIN_PARTIAL_LENGTH }

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

function Rank.ParseQuery(keywords, queryWords)
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
function Rank.Score(entry, query, rows)
    local name, nameTier = NameScore(entry, query, rows)
    local category, categoryTier = CategoryScore(entry, query, rows)
    if category and (not name or category > name) then
        return category, categoryTier
    end
    return name, nameTier
end

function Rank.Sort(results, scores)
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
end

Rank.StartsWith = StartsWith
Rank.TypoLimit = TypoLimit
Rank.IsTypoMatch = IsTypoMatch
Addon.LandmarkRank = table.freeze(Rank)
