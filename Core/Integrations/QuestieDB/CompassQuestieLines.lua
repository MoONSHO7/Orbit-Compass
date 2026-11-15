local _, Addon = ...
local L = Addon.L
local Readable = Addon.SourceUtils.Readable
local MAX_NAMES = 3
local NAME_SEPARATOR = ", "
local WHITE = table.freeze({ r = 1, g = 1, b = 1 })
local MUTED = 0.7
local Lines = {}

function Lines.Quest(level, title)
    if not level then
        return { text = title, r = WHITE.r, g = WHITE.g, b = WHITE.b }
    end
    local color = type(GetQuestDifficultyColor) == "function" and Readable(GetQuestDifficultyColor(level))
    color = type(color) == "table" and color or WHITE
    return { text = L.PLU_COMPASS_QUEST_LEVEL_F:format(level, title), r = color.r, g = color.g, b = color.b }
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
