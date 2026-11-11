local _, Addon = ...
local C = Addon.Constants
local F = Addon.ClientFeatures
local Utils = Addon.SourceUtils
local Readable = Utils.Readable

local PIN_KEYS = {}
for name, prefix in pairs({ AreaPOI = "poi:", TaxiNode = "taxi:", DigSite = "digSite:" }) do
    local value = Enum.SuperTrackingMapPinType[name]
    if value ~= nil and (name ~= "DigSite" or F.digSites) then
        PIN_KEYS[value] = prefix
    end
end
local QUEST_KEY = "quest:"

local function ReadAtlas(atlas, fallback)
    atlas = Readable(atlas)
    return Addon.Artwork.Resolve(type(atlas) == "string" and atlas ~= "" and atlas or fallback)
end

local function InMap(x, y)
    return x ~= nil and y ~= nil and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

local function Landmark(key, pinType, id, mapID, position, name, atlas, kind, place)
    if not F.AllowsKind(kind) then
        return
    end
    local x, y = Utils.ReadPosition(position)
    name = Readable(name)
    if not InMap(x, y) or type(name) ~= "string" or name == "" then
        return
    end
    local zone = place.zone ~= name and place.zone or nil
    local continent = place.continent ~= name and place.continent ~= zone and place.continent or nil
    local landmark = {
        indexed = true,
        key = key .. id,
        pinType = pinType,
        id = id,
        questID = key == QUEST_KEY and id or nil,
        mapID = mapID,
        x = x,
        y = y,
        name = name,
        atlas = ReadAtlas(atlas, C.FALLBACK_ATLAS),
        kind = kind,
        zone = zone,
        continent = continent,
    }
    return landmark
end

Addon.LandmarkRecord = table.freeze({
    New = Landmark,
    InMap = InMap,
    ReadAtlas = ReadAtlas,
    PinKeys = table.freeze(PIN_KEYS),
    QuestKey = QUEST_KEY,
})
