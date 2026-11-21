local _, Addon = ...
local L = Addon.L
local Readable, Number = Addon.SourceUtils.Readable, Addon.SourceUtils.Number
local MAX_NAMES = 3
local NAME_SEPARATOR = ", "
local WHITE = table.freeze({ r = 1, g = 1, b = 1 })
local MUTED = 0.7
-- One line per quest of the bridge's shared log snapshot, kept only while that snapshot holds the quest.
local questLines = setmetatable({}, { __mode = "k" })
local Lines = {}

function Lines.Quest(level, title)
    if not level then
        return { text = title, r = WHITE.r, g = WHITE.g, b = WHITE.b }
    end
    local color = type(GetQuestDifficultyColor) == "function" and Readable(GetQuestDifficultyColor(level))
    color = type(color) == "table" and color or WHITE
    return { text = L.PLU_COMPASS_QUEST_LEVEL_F:format(level, title), r = color.r, g = color.g, b = color.b }
end

-- The log quest's title line, nil for a quest without a title.
function Lines.ForQuest(quest)
    local line = questLines[quest]
    if line == nil then
        line = quest.title and Lines.Quest(quest.level, quest.title) or false
        questLines[quest] = line
    end
    return line or nil
end

-- A suggested level, or range, in the colour a quest of its level nearest the player's would have.
function Lines.Level(low, high)
    local level = Number(UnitLevel("player"))
    local color = type(GetQuestDifficultyColor) == "function"
        and Readable(GetQuestDifficultyColor(level and math.max(low, math.min(high, level)) or low))
    color = type(color) == "table" and color or WHITE
    local text = low == high and tostring(low) or L.PLU_COMPASS_LEVEL_RANGE_F:format(low, high)
    return { text = text, r = color.r, g = color.g, b = color.b }
end

function Lines.Plain(text)
    return { text = text, r = WHITE.r, g = WHITE.g, b = WHITE.b }
end

function Lines.Sources(sources)
    local names, unnamed = {}, 0
    for _, source in ipairs(sources) do
        if source.name and #names < MAX_NAMES then
            names[#names + 1] = source.name
        else
            unnamed = unnamed + 1
        end
    end
    if #names == 0 then
        return
    end
    local text = table.concat(names, NAME_SEPARATOR)
    if unnamed > 0 then
        text = L.PLU_COMPASS_QUEST_MORE_F:format(text, unnamed)
    end
    return { text = text, r = MUTED, g = MUTED, b = MUTED }
end

Addon.CompassQuestieLines = table.freeze(Lines)
