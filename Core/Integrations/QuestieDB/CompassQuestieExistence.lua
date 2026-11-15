local _, Addon = ...
local Plugin = Addon.Controller
local Utils = Addon.SourceUtils
local Readable, Number, Text = Utils.Readable, Utils.Number, Utils.Text
local RESULT_EVENT = "QUEST_DATA_LOAD_RESULT"
local BATCH, REQUEST_SECONDS = 8, 0.1
local COALESCE_SECONDS = 0.25
-- No confirmed quest this long after the first request means the client's answers cannot be trusted either way.
local CALIBRATION_SECONDS = 5
local PROFILER_LABEL = "Compass.QuestieDB.Existence"
local Existence = {}

local publish = Addon.LibOrbitUI.Callbacks:Wrap(function()
    local state = Plugin.compassQuestieExistence
    if state then
        state.publishing = false
        Plugin:InvalidateCompassMapPoints()
    end
end, PROFILER_LABEL)

local function Publish(state)
    if not state.publishing then
        state.publishing = true
        C_Timer.After(COALESCE_SECONDS, publish)
    end
end

-- A client that never confirms any quest gives no evidence, so its denials stop hiding quests.
local calibrate = Addon.LibOrbitUI.Callbacks:Wrap(function()
    local state = Plugin.compassQuestieExistence
    if state and not state.trusted then
        state.unsupported = true
        Publish(state)
    end
end, PROFILER_LABEL)

local pump
pump = Addon.LibOrbitUI.Callbacks:Wrap(function()
    local state = Plugin.compassQuestieExistence
    if not state then
        return
    end
    state.pumping = false
    for _ = 1, BATCH do
        local questID = table.remove(state.queue)
        if not questID then
            return
        end
        C_QuestLog.RequestLoadQuestByID(questID)
    end
    if #state.queue > 0 then
        state.pumping = true
        C_Timer.After(REQUEST_SECONDS, pump)
    end
end, PROFILER_LABEL)

local function Ask(plugin, state, questID)
    state.asked[questID] = true
    state.queue[#state.queue + 1] = questID
    if not state.listening then
        state.listening = true
        if C_EventUtils.IsEventValid(RESULT_EVENT) then
            plugin.events:RegisterEvent(RESULT_EVENT)
        end
        C_Timer.After(CALIBRATION_SECONDS, calibrate)
    end
    if not state.pumping then
        state.pumping = true
        C_Timer.After(REQUEST_SECONDS, pump)
    end
end

-- QuestieDB lists quests this game version never had. Only the game can say which, so a quest draws once the
-- client holds its data or the server answers for it; one it denies, or has not answered yet, stays hidden.
function Existence.Allows(plugin, questID)
    local state = plugin.compassQuestieExistence
    if not state then
        state = { known = {}, asked = {}, queue = {} }
        plugin.compassQuestieExistence = state
    end
    local known = state.known[questID]
    if known == nil and Text(C_QuestLog.GetTitleForQuestID(questID)) then
        state.known[questID], state.trusted, known = true, true, true
    elseif known == nil and not state.asked[questID] then
        Ask(plugin, state, questID)
    end
    return known == true or (state.unsupported == true and not state.trusted)
end

function Plugin:NoteCompassQuestExistence(questID, success)
    local state = self.compassQuestieExistence
    questID = Number(questID)
    if not (state and questID and state.asked[questID]) then
        return
    end
    local exists = Readable(success) == true
    if state.known[questID] ~= exists then
        state.known[questID] = exists
        state.trusted = state.trusted or exists
        Publish(state)
    end
end

Addon.CompassQuestieExistence = table.freeze(Existence)
