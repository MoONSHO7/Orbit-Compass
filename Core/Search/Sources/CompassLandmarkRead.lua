local _, Addon = ...
local Readable = Addon.SourceUtils.Readable

local function ReadList(value, checkpoint)
    value = Readable(value)
    checkpoint(value ~= false and type(value) ~= "table")
    return type(value) == "table" and value or {}
end

-- Fixed places are normalized once per root; `static` nil reads natively for a single map lookup.
local function StaticRecords(static, source, mapID, checkpoint, read, normalize)
    local cache = static and static[source]
    local records = cache and cache[mapID]
    if records then
        return records
    end
    local value = Readable(read(mapID))
    checkpoint(value ~= false and type(value) ~= "table")
    if value ~= false and type(value) ~= "table" then
        return {}
    end
    records = {}
    for _, item in ipairs(value or {}) do
        records[#records + 1] = normalize(Readable(item))
        checkpoint()
    end
    if cache then
        cache[mapID] = records
    end
    return records
end

Addon.LandmarkRead = table.freeze({
    List = ReadList,
    StaticRecords = StaticRecords,
})
