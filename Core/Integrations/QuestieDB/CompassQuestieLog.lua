local _, Addon = ...
local Plugin = Addon.Controller
local Utils = Addon.SourceUtils
local Readable, Number, Text = Utils.Readable, Utils.Number, Utils.Text
local Lines = Addon.CompassQuestieLines
local COALESCE_SECONDS = 0.25
-- Half the host's 60-second refresh, so each backstop collection reads the log again.
local MAX_AGE_SECONDS = 30
-- Longer than the host's refresh: without a collection for this long no map shows the log, so bursts stop reading.
local IDLE_SECONDS = 90
local FIELD_SEPARATOR, QUEST_SEPARATOR = "\1", "\2"
local PROFILER_LABEL = "Compass.QuestieDB.Log"
local CHANGED_COUNT, UNCHANGED_COUNT, EVENT_COUNT =
    "QuestieDB/Log/Changed", "QuestieDB/Log/Unchanged", "QuestieDB/Log/Event"
local NONE = table.freeze({})
local Log = {}

local function ByID(first, second)
    return first.id < second.id
end

local function Objectives(questID, parts)
    local rows = Readable(C_QuestLog.GetQuestObjectives(questID))
    local objectives = {}
    for position, row in ipairs(type(rows) == "table" and rows or NONE) do
        row = Readable(row)
        local known = type(row) == "table"
        local objective = {
            text = known and Text(row.text) or nil,
            type = known and Text(row.type) or nil,
            finished = known and Readable(row.finished) == true,
        }
        objectives[position] = objective
        parts[#parts + 1] = (objective.finished and "+" or "-") .. (objective.type or "") .. (objective.text or "")
    end
    return objectives
end

local function Take(state)
    local quests, byID, parts = {}, {}, {}
    for position = 1, Number(C_QuestLog.GetNumQuestLogEntries()) or 0 do
        local info = Readable(C_QuestLog.GetInfo(position))
        local questID = type(info) == "table" and Number(info.questID)
        if questID and questID > 0 and Readable(info.isHeader) ~= true and Readable(info.isHidden) ~= true then
            local title = Text(info.title) or Text(state.lib.Quest.name(questID))
            local level = Number(info.level)
            level = level and level > 0 and level or nil
            local complete = Readable(C_QuestLog.IsComplete(questID)) == true
                or Readable(C_QuestLog.ReadyForTurnIn(questID)) == true
            local failed = Readable(C_QuestLog.IsFailed(questID)) == true
            parts[#parts + 1] = QUEST_SEPARATOR
                .. questID
                .. (failed and "f" or complete and "c" or "-")
                .. (level or 0)
                .. (title or "")
            local quest = {
                id = questID,
                title = title,
                line = title and Lines.Quest(level, title) or nil,
                complete = complete,
                failed = failed,
                objectives = Objectives(questID, parts),
            }
            quests[#quests + 1], byID[questID] = quest, quest
        end
    end
    table.sort(quests, ByID)
    local faction = Readable(UnitFactionGroup("player"))
    local snapshot = {
        quests = quests,
        byID = byID,
        signature = table.concat(parts, FIELD_SEPARATOR),
        factionLetter = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil,
        readAt = GetTime(),
    }
    state.snapshot, state.stale = snapshot, false
    return snapshot
end

-- A burst only changes the host's rows when the log itself did, or the client moved a pin: a turn-in is matched
-- to its quest's pin, so any quest in the log can depend on one.
local refresh = Addon.LibOrbitUI.Callbacks:Wrap(function()
    local state = Plugin.compassQuestieLog
    if not state then
        return
    end
    local before, pins = state.snapshot, state.pins
    state.pending, state.pins = false, false
    local profiler = Addon.Services.profiler
    profiler = profiler and profiler.active and profiler
    local start, startKB
    if profiler then
        start, startKB = profiler:Begin()
    end
    local snapshot = Take(state)
    local changed = not before or before.signature ~= snapshot.signature or pins and #snapshot.quests > 0
    if changed then
        Plugin:InvalidateCompassMapPoints()
    end
    if profiler then
        profiler:End(Plugin, PROFILER_LABEL, start, startKB)
        profiler:Count(Plugin, changed and CHANGED_COUNT or UNCHANGED_COUNT)
    end
end, PROFILER_LABEL)

function Log.Read(plugin, lib)
    local state = plugin.compassQuestieLog
    if not state then
        state = { stale = true, pending = false, pins = false }
        plugin.compassQuestieLog = state
    end
    local now = GetTime()
    state.lib, state.usedAt = lib, now
    local snapshot = state.snapshot
    if state.stale or now - snapshot.readAt >= MAX_AGE_SECONDS then
        snapshot = Take(state)
    end
    return snapshot
end

-- Disabling Compass forgets the snapshot, so changes missed while it was off are read on the next collection.
function Log.Forget(plugin)
    plugin.compassQuestieLog = nil
end

-- Discovery routes quest-log events here: `burst` ones are coalesced, the rest make the next collection read anew.
function Plugin:NoteCompassQuestieLog(event, burst)
    local state = self.compassQuestieLog
    if not state then
        return
    end
    if not burst or not self.showQuestObjectives or GetTime() - state.usedAt >= IDLE_SECONDS then
        state.stale = true
        return
    end
    state.pins = state.pins or event == "QUEST_POI_UPDATE"
    local profiler = Addon.Services.profiler
    if profiler and profiler.active then
        profiler:Count(self, EVENT_COUNT)
    end
    if not state.pending then
        state.pending = true
        C_Timer.After(COALESCE_SECONDS, refresh)
    end
end

Addon.CompassQuestieLog = table.freeze(Log)
