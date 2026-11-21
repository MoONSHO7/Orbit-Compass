local _, Addon = ...
local L = Addon.L
local Readable = Addon.SourceUtils.Readable
local Hidden, Hints = Addon.CompassQuestieHidden, Addon.CompassQuestieHints
local Questie = LibStub("LibOrbitBridge-1.0").Questie
local MAX_MAPS = 8
local SOURCE = "questie"
-- What a row's right-click is named after, the most useful of its quests' choices first.
local REMOVES, HIDES, SHOWS = 1, 2, 3
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

local function Label(choice)
    return choice == SHOWS and L.PLU_COMPASS_MAP_HINT_SHOW
        or choice == HIDES and L.PLU_COMPASS_MAP_HINT_HIDE
        or L.PLU_COMPASS_MAP_REMOVE
end

-- A row that stands for a quest offers the host's right-click, named in `menu`. `hinted` tells whether the quest's
-- hint shows, for a row that can show or hide it; without it, or with `removable`, the quest can leave the map.
function Menu.Add(rows, row, questID, title, hinted, removable)
    local quests = rows[row.key]
    if not quests then
        quests = { choice = REMOVES }
        rows[row.key] = quests
    end
    quests.choice = math.max(quests.choice, hinted == false and SHOWS or hinted and HIDES or REMOVES)
    row.menu = Label(quests.choice)
    for _, quest in ipairs(quests) do
        if quest.id == questID then
            return
        end
    end
    quests[#quests + 1] =
        { id = questID, title = title or tostring(questID), hint = hinted ~= nil, remove = hinted == nil or removable }
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

local function Completed(questID)
    return Readable(C_QuestLog.IsQuestFlaggedCompleted(questID)) == true
end

-- Showing a hint also drops the hints of quests completed since, so the saved list never outgrows the character.
local function ToggleHint(plugin, questID)
    if Hints.Has(plugin, questID) then
        Hints.Remove(plugin, questID)
    else
        Hints.Add(plugin, questID, Completed)
    end
    Refresh(plugin)
end

-- One titled group of the row's quests that pass `wanted`, divided from any group before it.
local function Section(root, quests, title, wanted, run, divide)
    local opened = false
    for _, quest in ipairs(quests) do
        if wanted(quest) then
            if not opened then
                opened = true
                if divide then
                    root:CreateDivider()
                end
                root:CreateTitle(title)
            end
            root:CreateButton(quest.title, function()
                run(quest.id)
            end)
        end
    end
    return opened
end

-- Fills the host's context menu for one row: showing or hiding the hint of each quest it can, removing each quest
-- it can from the map, and bringing every removed quest back.
function Menu.Build(plugin, key, root)
    local quests = Quests(plugin, key)
    local function Toggle(questID)
        ToggleHint(plugin, questID)
    end
    local filled = Section(root, quests, L.PLU_COMPASS_MAP_HINT_SHOW, function(quest)
        return quest.hint and not Hints.Has(plugin, quest.id)
    end, Toggle)
    filled = Section(root, quests, L.PLU_COMPASS_MAP_HINT_HIDE, function(quest)
        return quest.hint and Hints.Has(plugin, quest.id)
    end, Toggle, filled) or filled
    local removes = Section(root, quests, L.PLU_COMPASS_MAP_REMOVE, function(quest)
        return quest.remove
    end, function(questID)
        Hidden.Add(plugin, questID)
        Refresh(plugin)
    end, filled)
    local count = Hidden.Count(plugin)
    -- A row whose quests can only show or hide a hint is not where removed quests come back.
    if count > 0 and (removes or not filled) then
        if removes then
            root:CreateDivider()
        else
            root:CreateTitle(L.PLU_COMPASS_MAP_REMOVE)
        end
        root:CreateButton(L.PLU_COMPASS_MAP_RESTORE_F:format(count), function()
            Hidden.Clear(plugin)
            Refresh(plugin)
        end)
    end
end

local function Snapshot(plugin)
    local lib = plugin.showQuestObjectives and Questie.Provider()
    local index = lib and Questie.Request(plugin, lib)
    if index then
        return index, Questie.ReadLog(lib)
    end
end

-- What a right-click offers on a quest the host draws itself (its own pin, its tracker row): hiding the QuestieDB
-- hint that shows, or showing one when QuestieDB places an objective the quest still needs. Nil otherwise.
function Menu.QuestHint(plugin, questID)
    local index, snapshot = Snapshot(plugin)
    local quest = index and snapshot.byID[questID]
    if not quest or quest.complete or quest.failed then
        return nil
    end
    if Hints.Has(plugin, questID) then
        return L.PLU_COMPASS_MAP_HINT_HIDE
    end
    local plan = Questie.Plan(index, questID)
    return plan and Questie.Locates(plan, quest.objectives) and L.PLU_COMPASS_MAP_HINT_SHOW or nil
end

-- Adds that choice to a menu of the host's.
function Menu.BuildQuest(plugin, questID, root)
    local text = Menu.QuestHint(plugin, questID)
    if text then
        root:CreateButton(text, function()
            ToggleHint(plugin, questID)
        end)
    end
end

Addon.CompassQuestieMenu = table.freeze(Menu)
