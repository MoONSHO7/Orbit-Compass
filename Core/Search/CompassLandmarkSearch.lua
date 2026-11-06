local _, Addon = ...
local L = Addon.L
local C = Addon.Constants
local Plugin = Addon.Controller
local Rank = Addon.LandmarkRank
local Keywords = Addon.LandmarkKeywords
local QueryIndex = Addon.LandmarkQueryIndex
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local Text = Addon.Text
local Fold, Words, AddSearchFields = Text.Fold, Text.Words, Text.AddSearchFields
local MIN_QUERY_LENGTH = 2
local FUZZY_RESULT_THRESHOLD = 12
local QUEST_PROGRESS_ATLAS = "Quest-In-Progress-Icon-yellow"
local QUEST_COMPLETE_ATLAS = "UI-QuestIcon-TurnIn-Normal"
local LIVE_MARKER_EXCLUDED = { route = true, waypoint = true, corpse = true, directions = true }
local function MapName(info)
    local name = type(info) == "table" and Readable(info.name)
    return type(name) == "string" and name or nil
end

local function LiveEntry(fields, zone)
    fields.zone = zone
    return AddSearchFields(fields, fields.name, zone)
end

local function SavedLocations(plugin, consider, readMapInfo)
    for _, location in pairs(plugin.compassLocations:Records()) do
        local name = type(location) == "table" and Readable(location.name)
        local mapID = type(name) == "string" and Number(location.mapID)
        local usable, info
        if mapID then
            usable, info = plugin:IsCompassLocationUsable(location, readMapInfo)
        end
        if usable then
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
            }, MapName(info)))
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

local function CompassMarkers(plugin, consider, indexed, readMapInfo)
    local zone = MapName(plugin.mapID and readMapInfo(plugin.mapID))
    local rows = plugin.compassLiveMarkers
    for _, marker in ipairs(plugin.markers) do
        if not LIVE_MARKER_EXCLUDED[marker.kind] then
            local entry = rows.previous[marker]
            if entry and entry.zone ~= zone then
                entry = nil
            end
            if not entry and not indexed[marker.key] then
                local fields =
                    { kind = marker.kind, key = marker.key, name = marker.name, atlas = marker.atlas, marker = marker }
                for _, field in ipairs(C.MARKER_ART_FIELDS) do
                    fields[field] = marker[field]
                end
                entry = LiveEntry(fields, zone)
            end
            if entry then
                rows.current[marker] = entry
                rows.previous[marker] = nil
                if not indexed[marker.key] then
                    consider(entry)
                end
            end
        end
    end
    wipe(rows.previous)
    rows.previous, rows.current = rows.current, rows.previous
end

function Plugin:NewCompassSearchScratch()
    return { scores = {}, tiers = {}, candidates = {}, marked = {} }
end

local function IsScoredQuery(folded)
    return strlenutf8(folded) >= MIN_QUERY_LENGTH
end

function Plugin:IsScoredCompassQuery(text)
    return IsScoredQuery(Fold(text))
end

-- Callers own their scratch so the inline field and an Orbit search session never share score tables.
function Plugin:SearchCompassLandmarks(text, results, scratch, options)
    wipe(results)
    local scores, tiers = scratch.scores, scratch.tiers
    wipe(scores)
    wipe(tiers)
    local fuzzy = not options or options.fuzzy ~= false
    local folded = Fold(text)
    if not IsScoredQuery(folded) then
        return results
    end
    local profiler = Addon.Services.profiler
    local start, startKB
    if profiler then
        start, startKB = profiler:Begin()
    end
    self.compassSearchKeywords = self.compassSearchKeywords or Keywords.Build()
    self.compassSearchRows = self.compassSearchRows or { target = {}, twoBack = {}, previous = {}, current = {} }
    self.compassLiveMarkers = self.compassLiveMarkers or { previous = {}, current = {} }
    local words = Words(folded)
    local kinds, rest = Rank.ParseQuery(self.compassSearchKeywords, words)
    local query = {
        text = folded,
        padded = " " .. folded,
        words = words,
        letters = (string.gsub(folded, " ", "")),
        kinds = kinds,
        rest = rest,
    }
    local live = {}
    local maps = {}
    local function ReadMapInfo(mapID)
        local info = maps[mapID]
        if info == nil then
            info = Readable(C_Map.GetMapInfo(mapID))
            maps[mapID] = type(info) == "table" and info or false
        end
        return info
    end
    local function Collect(entry)
        if Addon.ClientFeatures.AllowsKind(entry.kind) then
            live[#live + 1] = entry
        end
    end
    local indexed = self.compassLandmarks.positions
    if Addon.ClientFeatures.quests then
        QuestLog(self, Collect, indexed)
    end
    CompassMarkers(self, Collect, indexed, ReadMapInfo)
    SavedLocations(self, Collect, ReadMapInfo)
    local landmarks = self:GetCompassLandmarks()
    local queryIndex = self.compassLandmarks.queryIndex
    -- The first build's completion notice re-runs this query with the fuzzy pass and the new index.
    local unindexed = self:IsCompassLandmarkSearchUnindexed()
    local counting = profiler and profiler.active
    local function Visit(entry, rows)
        if Addon.ClientFeatures.AllowsKind(entry.kind) and not scores[entry] then
            local score, tier = Rank.Score(entry, query, rows)
            if score then
                results[#results + 1] = entry
                scores[entry], tiers[entry] = score, tier
            end
        end
    end
    local function Pass(rows)
        if queryIndex then
            QueryIndex.MarkCandidates(queryIndex, query, rows, scratch)
            for _, index in ipairs(scratch.candidates) do
                Visit(queryIndex.entries[index], rows)
            end
        else
            for _, entry in ipairs(landmarks) do
                Visit(entry, rows)
            end
        end
        for _, entry in ipairs(live) do
            Visit(entry, rows)
        end
    end
    if unindexed and counting then
        profiler:Count(self, "Search/Unindexed")
    end
    Pass(nil)
    if fuzzy and #results < FUZZY_RESULT_THRESHOLD then
        if unindexed then
            if counting then
                profiler:Count(self, "Search/FuzzySkipped")
            end
        else
            local fuzzyStart, fuzzyKB
            if profiler then
                fuzzyStart, fuzzyKB = profiler:Begin()
            end
            self.compassSearchRows.matches = {}
            Pass(self.compassSearchRows)
            self.compassSearchRows.matches = nil
            if fuzzyStart then
                profiler:End(self, "Compass.Search.Fuzzy", fuzzyStart, fuzzyKB)
            end
        end
    end
    Rank.Sort(results, scores)
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
