local _, Addon = ...
local Rank = Addon.LandmarkRank
local StartsWith, TypoLimit, IsTypoMatch = Rank.StartsWith, Rank.TypoLimit, Rank.IsTypoMatch
local MIN_PARTIAL_LENGTH = Rank.MIN_PARTIAL_LENGTH
local LINE_BREAK = "\n"

local QueryIndex = {}

local function MarkCandidate(scratch, index)
    if not scratch.marked[index] then
        scratch.marked[index] = true
        scratch.candidates[#scratch.candidates + 1] = index
    end
end

local function MarkPostings(scratch, postings)
    for _, index in ipairs(postings) do
        MarkCandidate(scratch, index)
    end
end

local function LineAt(starts, cursor, position)
    while starts[cursor + 1] and starts[cursor + 1] <= position do
        cursor = cursor + 1
    end
    return cursor
end

local function MarkPlain(queryIndex, text, scratch)
    local blob, starts, cursor, init = queryIndex.blob, queryIndex.starts, 1, 1
    while true do
        local found = string.find(blob, text, init, true)
        if not found then
            return
        end
        cursor = LineAt(starts, cursor, found)
        MarkCandidate(scratch, cursor)
        init = starts[cursor + 1]
        if not init then
            return
        end
    end
end

local function OrderedPattern(letters)
    local parts = { LINE_BREAK }
    for position = 1, #letters do
        local letter = string.sub(letters, position, position)
        parts[#parts + 1] = "[^" .. LINE_BREAK .. letter .. "]*" .. letter
    end
    return table.concat(parts)
end

local function MarkOrdered(queryIndex, letters, scratch)
    local blob, starts, cursor, init = queryIndex.blob, queryIndex.starts, 1, 1
    local pattern = OrderedPattern(letters)
    while true do
        local found = string.find(blob, pattern, init)
        if not found then
            return
        end
        cursor = LineAt(starts, cursor, found + #LINE_BREAK)
        MarkCandidate(scratch, cursor)
        init = starts[cursor + 1]
        if not init then
            return
        end
        init = init - #LINE_BREAK
    end
end

local function LongestWord(words)
    local longest = words[1]
    for _, word in ipairs(words) do
        if #word > #longest then
            longest = word
        end
    end
    return longest
end

local function MarkWord(queryIndex, word, rows, scratch)
    local bucket = queryIndex.buckets[string.byte(word, 1)]
    if not bucket then
        return
    end
    local limit = rows and TypoLimit(word) or 0
    for _, target in ipairs(bucket) do
        if StartsWith(target, word) or (limit > 0 and IsTypoMatch(word, target, limit, rows)) then
            MarkPostings(scratch, queryIndex.postings[target])
        end
    end
end

function QueryIndex.MarkCandidates(queryIndex, query, rows, scratch)
    wipe(scratch.marked)
    wipe(scratch.candidates)
    MarkPlain(queryIndex, query.text, scratch)
    MarkWord(queryIndex, LongestWord(query.words), rows, scratch)
    if query.kinds and #query.rest == 0 then
        for kind in pairs(query.kinds) do
            local list = queryIndex.kinds[kind]
            if list then
                MarkPostings(scratch, list)
            end
        end
    elseif query.kinds then
        MarkWord(queryIndex, LongestWord(query.rest), rows, scratch)
    end
    if rows and #query.letters >= MIN_PARTIAL_LENGTH then
        MarkOrdered(queryIndex, query.letters, scratch)
    end
    table.sort(scratch.candidates)
end

local function AddPosting(queryIndex, word, index)
    local postings = queryIndex.postings[word]
    if not postings then
        postings = {}
        queryIndex.postings[word] = postings
        local first = string.byte(word, 1)
        local bucket = queryIndex.buckets[first]
        if not bucket then
            bucket = {}
            queryIndex.buckets[first] = bucket
        end
        bucket[#bucket + 1] = word
    end
    if postings[#postings] ~= index then
        postings[#postings + 1] = index
    end
end

function QueryIndex.Build(entries, checkpoint, phase)
    if phase then
        phase("Compass.Landmarks.QueryIndex.Entries")
    end
    local queryIndex = { entries = entries, starts = {}, buckets = {}, postings = {}, kinds = {} }
    local texts, start = {}, #LINE_BREAK + 1
    for index, entry in ipairs(entries) do
        texts[index], queryIndex.starts[index] = entry.searchText, start
        start = start + #entry.searchText + #LINE_BREAK
        for _, word in ipairs(entry.nameWords) do
            AddPosting(queryIndex, word, index)
        end
        for _, word in ipairs(entry.placeWords) do
            AddPosting(queryIndex, word, index)
        end
        local kind = queryIndex.kinds[entry.kind]
        if not kind then
            kind = {}
            queryIndex.kinds[entry.kind] = kind
        end
        kind[#kind + 1] = index
        checkpoint()
    end
    if phase then
        phase("Compass.Landmarks.QueryIndex.Blob")
    end
    queryIndex.blob = LINE_BREAK .. table.concat(texts, LINE_BREAK) .. LINE_BREAK
    return queryIndex
end

Addon.LandmarkQueryIndex = table.freeze(QueryIndex)
