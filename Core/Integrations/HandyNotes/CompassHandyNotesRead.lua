local _, Addon = ...
local Readable = Addon.SourceUtils.Readable
local Read = {}

function Read.Table(value)
    value = Readable(value)
    if type(value) == "table" then
        return value
    end
end

function Read.String(value)
    value = Readable(value)
    if type(value) == "string" and value ~= "" then
        return value
    end
end

function Read.Callable(value)
    value = Readable(value)
    if type(value) == "function" then
        return value
    end
end

Addon.HandyNotesRead = table.freeze(Read)
