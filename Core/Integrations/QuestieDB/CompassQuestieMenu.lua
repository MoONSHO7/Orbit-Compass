local _, Addon = ...
local L = Addon.L
local Hidden = Addon.CompassQuestieHidden
local MAX_MAPS = 8
local SOURCE = "questie"
local NONE = table.freeze({})
local Menu = {}

-- The quests each row of one map stands for, replaced whenever that map is collected again.
function Menu.Begin(plugin, mapID)
    local maps = plugin.compassQuestieMenus or {}
    plugin.compassQuestieMenus = maps
    if not maps[mapID] then
        local count = 0
        for _ in pairs(maps) do
            count = count + 1
        end
        if count >= MAX_MAPS then
            wipe(maps)
        end
    end
    local rows = {}
    maps[mapID] = rows
    return rows
end

-- A row that stands for a quest offers the host's right-click; `menu` is the hint the host shows for it.
function Menu.Add(rows, row, questID, title)
    local quests = rows[row.key]
    if not quests then
        quests = {}
        rows[row.key], row.menu = quests, L.PLU_COMPASS_MAP_REMOVE
    end
    for _, quest in ipairs(quests) do
        if quest.id == questID then
            return
        end
    end
    quests[#quests + 1] = { id = questID, title = title or tostring(questID) }
end

local function Quests(plugin, key)
    for _, rows in pairs(plugin.compassQuestieMenus or NONE) do
        if rows[key] then
            return rows[key]
        end
    end
    return NONE
end

local function Refresh(plugin)
    plugin:InvalidateCompassSourceSettings(SOURCE)
end

-- Fills the host's context menu for one row: each quest it stands for can leave the map, and all can come back.
function Menu.Build(plugin, key, root)
    root:CreateTitle(L.PLU_COMPASS_MAP_REMOVE)
    for _, quest in ipairs(Quests(plugin, key)) do
        root:CreateButton(quest.title, function()
            Hidden.Add(plugin, quest.id)
            Refresh(plugin)
        end)
    end
    local count = Hidden.Count(plugin)
    if count > 0 then
        root:CreateDivider()
        root:CreateButton(L.PLU_COMPASS_MAP_RESTORE_F:format(count), function()
            Hidden.Clear(plugin)
            Refresh(plugin)
        end)
    end
end

Addon.CompassQuestieMenu = table.freeze(Menu)
