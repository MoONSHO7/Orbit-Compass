local _, Addon = ...
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local Objectives, Log, Lines = Addon.CompassQuestieObjectives, Addon.CompassQuestieLog, Addon.CompassQuestieLines
local Menu, Hidden = Addon.CompassQuestieMenu, Addon.CompassQuestieHidden
local OBJECTIVE_SCALE = 0.6
-- Turn-ins and objective icons one map may show together: ten objectives at their full 24 spots.
local MAX_MAP_ROWS = 240
local MAX_LINES = 16
-- About one icon's width on the host's map: a QuestieDB turn-in this close to the client's pin is the same place.
local TURN_IN_DISTANCE = 0.03
local TURN_IN_ATLAS = "UI-QuestIcon-TurnIn-Normal"
local KIND_ATLASES = {
    creature = "Crosshair_attack_32",
    credit = "Crosshair_attack_32",
    object = "Crosshair_interact_32",
    item = "Crosshair_lootall_32",
    event = "VignetteEvent",
}
local FALLBACK_ATLAS = "Bonus-Objective-Star"
local LISTS_SOURCES = { item = true, credit = true }
local NONE = table.freeze({})
local Rows = {}

local function Aligned(plan, live)
    if #live ~= #plan.objectives then
        return false
    end
    for position, objective in ipairs(plan.objectives) do
        if objective.type and live[position].type ~= objective.type then
            return false
        end
    end
    return true
end

local function Serves(snapshot, source)
    local faction = source.faction
    return source.entity == "object"
        or faction ~= nil and snapshot.factionLetter ~= nil and faction:find(snapshot.factionLetter, 1, true) ~= nil
end

local function ClientPins(mapID)
    local pins = {}
    local quests = Readable(C_QuestLog.GetQuestsOnMap(mapID))
    for _, info in ipairs(type(quests) == "table" and quests or NONE) do
        info = Readable(info)
        local questID = type(info) == "table" and Number(info.questID)
        local x, y = Utils.ReadPosition(info)
        if questID and x and y then
            local points = pins[questID]
            if not points then
                points = {}
                pins[questID] = points
            end
            points[#points + 1], points[#points + 2] = x, y
        end
    end
    return pins
end

local function Pinned(points, spot)
    for cursor = 1, #(points or NONE), 2 do
        local dx, dy = points[cursor] - spot.x, points[cursor + 1] - spot.y
        if dx * dx + dy * dy <= TURN_IN_DISTANCE * TURN_IN_DISTANCE then
            return true
        end
    end
    return false
end

local function AddTurnIns(rows, snapshot, turnIns, mapID, limit, pins, menus)
    local byKey = {}
    for _, turnIn in ipairs(turnIns) do
        local quest, spot = turnIn.quest, turnIn.spot
        local finisher = spot.sources[1]
        if finisher.name and quest.line and Serves(snapshot, finisher) then
            pins = pins or ClientPins(mapID)
            if not Pinned(pins[quest.id], spot) then
                local key = ("turnin:%s:%d"):format(finisher.ref, spot.cell)
                local row = byKey[key]
                if not row and limit > 0 then
                    limit = limit - 1
                    row = { key = key, x = spot.x, y = spot.y, atlas = TURN_IN_ATLAS, name = finisher.name, lines = {} }
                    byKey[key], rows[#rows + 1] = row, row
                end
                if row and #row.lines < MAX_LINES then
                    row.lines[#row.lines + 1] = quest.line
                end
                if row then
                    Menu.Add(menus, row, quest.id, quest.line.text)
                end
            end
        end
    end
    return limit
end

local function Sharing(groups, spot)
    for _, group in ipairs(groups or NONE) do
        for _, source in ipairs(spot.sources) do
            if group.refs[source.ref] then
                return group
            end
        end
    end
end

-- Rank by rank, every objective keeps its densest cells before the map's cap trims anyone's sparser ones.
local function Group(tasks, limit)
    local groups, cells = {}, {}
    for rank = 1, Objectives.MAX_SPOTS do
        local ranked = false
        for _, task in ipairs(tasks) do
            local spot = task.spots[rank]
            if spot then
                ranked = true
                local group = Sharing(cells[spot.cell], spot)
                if not group and #groups < limit then
                    group = { refs = {}, entries = {} }
                    groups[#groups + 1] = group
                    local members = cells[spot.cell] or {}
                    cells[spot.cell], members[#members + 1] = members, group
                end
                if group then
                    group.entries[#group.entries + 1] = { task = task, spot = spot }
                    for _, source in ipairs(spot.sources) do
                        group.refs[source.ref] = true
                    end
                end
            end
        end
        if not ranked then
            break
        end
    end
    return groups
end

local function EarlierEntry(first, second)
    if first.task.quest.id ~= second.task.quest.id then
        return first.task.quest.id < second.task.quest.id
    end
    return first.task.position < second.task.position
end

local function GroupLines(entries)
    local lines, quest = {}, nil
    for _, entry in ipairs(entries) do
        local task = entry.task
        local text = task.live and task.live.text or task.objective.name
        local sources = LISTS_SOURCES[task.objective.kind] and Lines.Sources(entry.spot.sources) or nil
        local title = task.quest ~= quest and task.quest.line or nil
        if #lines + (title and 1 or 0) + (text and 1 or 0) + (sources and 1 or 0) > MAX_LINES then
            break
        end
        quest = task.quest
        lines[#lines + 1] = title
        if text then
            lines[#lines + 1] = Lines.Plain(text)
        end
        lines[#lines + 1] = sources
    end
    return lines
end

local function ItemIcon(index, itemID)
    if not index.icons[itemID] then
        local icon = Number(C_Item.GetItemIconByID(itemID))
        index.icons[itemID] = icon and icon > 0 and icon or nil
    end
    return index.icons[itemID]
end

-- The lowest quest and objective owns key and place, so the host reuses the record while that objective is active.
local function GroupRow(index, group, menus)
    table.sort(group.entries, EarlierEntry)
    local owner = group.entries[1]
    local task, spot = owner.task, owner.spot
    local objective = task.objective
    local name = objective.name or task.quest.title
    if not name then
        return
    end
    local texture = objective.itemID and ItemIcon(index, objective.itemID) or nil
    local atlas = not texture and KIND_ATLASES[objective.kind] or nil
    local row = {
        key = ("objective:%d:%d:%d"):format(task.quest.id, task.position, spot.cell),
        x = spot.x,
        y = spot.y,
        atlas = atlas and (Addon.Artwork.Exists(atlas) and atlas or FALLBACK_ATLAS) or nil,
        texture = texture,
        scale = OBJECTIVE_SCALE,
        name = name,
        lines = GroupLines(group.entries),
    }
    for _, entry in ipairs(group.entries) do
        local quest = entry.task.quest
        Menu.Add(menus, row, quest.id, quest.line and quest.line.text or quest.title)
    end
    return row
end

function Rows.Add(plugin, rows, index, mapID, menus)
    local snapshot = Log.Read(plugin, index.lib)
    local turnIns, tasks, pins = {}, {}, nil
    for _, quest in ipairs(snapshot.quests) do
        local shown = not quest.failed and not Hidden.Has(plugin, quest.id)
        local places = shown and Objectives.Places(index, quest.id, mapID)
        if places == nil then
            Objectives.Request(plugin, index, quest.id, mapID)
        elseif places then
            local plan, live = places.plan, quest.objectives
            if quest.complete or #live == 0 and #plan.objectives == 0 then
                for _, spot in ipairs(places.turnIns) do
                    turnIns[#turnIns + 1] = { quest = quest, spot = spot }
                end
            else
                pins = pins or ClientPins(mapID)
                -- The client's own pin or area marks a quest it shows on this map, so only other quests draw spots.
                if not pins[quest.id] then
                    -- Objectives that cannot be matched to the client's list all show, rather than none.
                    local aligned = Aligned(plan, live)
                    for position, objective in ipairs(plan.objectives) do
                        local spots = places.spots[position]
                        if spots and not (aligned and live[position].finished) then
                            tasks[#tasks + 1] = {
                                quest = quest,
                                objective = objective,
                                position = position,
                                spots = spots,
                                live = aligned and live[position] or nil,
                            }
                        end
                    end
                end
            end
        end
    end
    local limit = AddTurnIns(rows, snapshot, turnIns, mapID, MAX_MAP_ROWS, pins, menus)
    for _, group in ipairs(Group(tasks, limit)) do
        rows[#rows + 1] = GroupRow(index, group, menus)
    end
end

Addon.CompassQuestieLogRows = table.freeze(Rows)
