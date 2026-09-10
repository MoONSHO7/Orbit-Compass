local _, Addon = ...
local C = Addon.Constants
local IsSecret = Addon.Services.IsSecret
local Utils = {}

function Utils.Readable(value)
    if not IsSecret(value, "Compass.MapData") then
        return value
    end
end

function Utils.Number(value)
    value = Utils.Readable(value)
    if type(value) == "number" and value == value and math.abs(value) < math.huge then
        return value
    end
end

function Utils.ReadPosition(position)
    position = Utils.Readable(position)
    if type(position) == "table" then
        return Utils.Number(position.x), Utils.Number(position.y)
    end
end

function Utils.IsMapPosition(position)
    local x, y = Utils.ReadPosition(position)
    return x ~= nil and y ~= nil and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

function Utils.AddMarker(plugin, markers, key, position, name, atlas, priority, kind, destination)
    local x, y = Utils.ReadPosition(position)
    name, atlas = Utils.Readable(name), Utils.Readable(atlas)
    if not x or not y or type(name) ~= "string" or name == "" then
        return
    end
    if type(atlas) ~= "string" or atlas == "" then
        atlas = C.FALLBACK_ATLAS
    end
    local marker = {
        key = key,
        x = x,
        y = y,
        name = name,
        atlas = atlas,
        sizeScale = atlas:lower() == C.BASIC_CHEST_ATLAS and C.BASIC_CHEST_SCALE or 1,
        priority = priority,
        kind = kind,
        destination = destination or { mapID = plugin.mapID, x = x, y = y },
    }
    markers[#markers + 1] = marker
    return marker
end

Addon.SourceUtils = table.freeze(Utils)
