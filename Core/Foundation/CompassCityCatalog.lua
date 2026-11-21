local addonName, Addon = ...
local ADDON_ROOT = "Interface\\AddOns\\" .. addonName
local WHOLE_MAP = table.freeze({ 0, 0, 1, 1 })
local TOWN_TEXTURES = {
    goblin = "\\Assets\\Cities\\goblin.tga",
    horde = "\\Assets\\Cities\\horde.tga",
    town = "\\Assets\\Cities\\town.tga",
}
local OUTLINE_DIGITS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
local OUTLINE_ROW_SEPARATOR = "/"

-- The game flags almost none of these as cities (Retail: Valdrakken, Dornogal, Silvermoon; Forever: none), so each
-- client family lists its capitals and hubs by map. The first map supplies the bounds; the rest are its floors.
local CITIES = {
    retail = {
        { texture = "\\Assets\\Cities\\stormwind.tga", maps = { 84 }, faction = "Alliance" },
        { texture = "\\Assets\\Cities\\ironforge.tga", maps = { 87 }, faction = "Alliance" },
        { texture = "\\Assets\\Cities\\darnassus.tga", maps = { 89 }, faction = "Alliance" },
        { texture = "\\Assets\\Cities\\exodar.tga", maps = { 103, 775 }, faction = "Alliance" },
        { texture = "\\Assets\\Cities\\orgrimmar.tga", maps = { 85 }, faction = "Horde" },
        { texture = "\\Assets\\Cities\\thunderbluff.tga", maps = { 88 }, faction = "Horde" },
        { texture = "\\Assets\\Cities\\undercity.tga", maps = { 90, 998 }, faction = "Horde" },
        { texture = "\\Assets\\Cities\\silvermoon.tga", maps = { 110 }, faction = "Horde" },
        { texture = "\\Assets\\Cities\\silvermoon.tga", maps = { 2393, 2605 } },
        { texture = "\\Assets\\Cities\\shattrath.tga", maps = { 111 } },
        { texture = "\\Assets\\Cities\\dalaran.tga", maps = { 125, 126 } },
        { texture = "\\Assets\\Cities\\dalaran.tga", maps = { 627, 628, 629 } },
        { texture = "\\Assets\\Cities\\sevenstars.tga", maps = { 393, 394 }, faction = "Alliance" },
        { texture = "\\Assets\\Cities\\twomoons.tga", maps = { 391, 392 }, faction = "Horde" },
        { texture = "\\Assets\\Cities\\stormshield.tga", maps = { 622 }, faction = "Alliance" },
        { texture = "\\Assets\\Cities\\warspear.tga", maps = { 624 }, faction = "Horde" },
        { texture = "\\Assets\\Cities\\boralus.tga", maps = { 1161 }, faction = "Alliance" },
        { texture = "\\Assets\\Cities\\dazaralor.tga", maps = { 1165 }, faction = "Horde" },
        { texture = "\\Assets\\Cities\\oribos.tga", maps = { 1670, 1671, 1672, 1673 } },
        { texture = "\\Assets\\Cities\\valdrakken.tga", maps = { 2112 } },
        { texture = "\\Assets\\Cities\\dornogal.tga", maps = { 2339 } },
        { texture = "\\Assets\\Cities\\tazavesh.tga", maps = { 2472 } },
    },
    forever = {
        { texture = "\\Assets\\Cities\\stormwind.tga", maps = { 1453 }, faction = "Alliance" },
        { texture = "\\Assets\\Cities\\ironforge.tga", maps = { 1455 }, faction = "Alliance" },
        { texture = "\\Assets\\Cities\\darnassus.tga", maps = { 1457 }, faction = "Alliance" },
        { texture = "\\Assets\\Cities\\orgrimmar.tga", maps = { 1454 }, faction = "Horde" },
        { texture = "\\Assets\\Cities\\thunderbluff.tga", maps = { 1456 }, faction = "Horde" },
        { texture = "\\Assets\\Cities\\undercity.tga", maps = { 1458 }, faction = "Horde" },
    },
}

-- Runs are zero-based first/last chunk columns; rowStarts[row] indexes a row's first run, closed by a sentinel.
local function DecodeOutline(outline)
    local columns, text = outline:match("^(%d+):(.*)$")
    local runs, rowStarts = {}, { 1 }
    for index = 1, #text do
        local digit = text:sub(index, index)
        if digit == OUTLINE_ROW_SEPARATOR then
            rowStarts[#rowStarts + 1] = #runs + 1
        else
            runs[#runs + 1] = OUTLINE_DIGITS:find(digit, 1, true) - 1
        end
    end
    rowStarts[#rowStarts + 1] = #runs + 1
    return tonumber(columns), #rowStarts - 1, table.freeze(runs), table.freeze(rowStarts)
end

-- Cities are whole maps the client switches to on entry; towns are subzones outlined by their terrain chunks, inside a
-- rectangle on their zone map.
local family = Addon.ClientFeatures.family
local places, byMap = {}, {}
for _, entry in ipairs(CITIES[family] or {}) do
    local city = table.freeze({
        mapID = entry.maps[1],
        rect = WHOLE_MAP,
        texture = ADDON_ROOT .. entry.texture,
        faction = entry.faction,
    })
    places[#places + 1] = city
    for _, mapID in ipairs(entry.maps) do
        byMap[mapID] = city
    end
end
local outlines = Addon.CompassTownMasks[family] or {}
for _, town in ipairs(Addon.CompassTownCatalog[family] or {}) do
    local outline = outlines[town.area]
    local columns, rows, runs, rowStarts
    if outline then
        columns, rows, runs, rowStarts = DecodeOutline(outline)
    end
    places[#places + 1] = table.freeze({
        mapID = town.map,
        areaID = town.area,
        rect = table.freeze(town.rect),
        columns = columns,
        rows = rows,
        runs = runs,
        rowStarts = rowStarts,
        texture = ADDON_ROOT .. TOWN_TEXTURES[town.icon],
        faction = town.faction,
    })
end

Addon.CompassCityCatalog = table.freeze({ places = table.freeze(places), byMap = table.freeze(byMap) })
