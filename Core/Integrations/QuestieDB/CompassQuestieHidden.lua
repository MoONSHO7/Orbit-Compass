local _, Addon = ...

-- A list of quests the player chose on the host's map, kept with the character in the host plugin's store. Standalone
-- Compass has no such store and no map to choose on, so its lists stay empty.
local function QuestList(storeKey, field)
    local Quests = {}

    local function List(plugin)
        local list = plugin[field]
        if not list then
            list = {}
            local stored = plugin.GetCharData and plugin:GetCharData(storeKey)
            if type(stored) == "table" then
                for questID in pairs(stored) do
                    if type(questID) == "number" then
                        list[questID] = true
                    end
                end
            end
            plugin[field] = list
        end
        return list
    end

    local function Save(plugin, list)
        if plugin.SetCharData then
            local stored = {}
            for questID in pairs(list) do
                stored[questID] = true
            end
            plugin:SetCharData(storeKey, next(stored) and stored or nil)
        end
    end

    function Quests.Has(plugin, questID)
        return List(plugin)[questID] == true
    end

    function Quests.Count(plugin)
        local count = 0
        for _ in pairs(List(plugin)) do
            count = count + 1
        end
        return count
    end

    -- `retired`, when given, tells which other listed quests leave the list in the same save.
    function Quests.Add(plugin, questID, retired)
        local list = List(plugin)
        local changed = not list[questID]
        list[questID] = true
        for listed in pairs(list) do
            if retired and listed ~= questID and retired(listed) then
                list[listed], changed = nil, true
            end
        end
        if changed then
            Save(plugin, list)
        end
    end

    function Quests.Remove(plugin, questID)
        local list = List(plugin)
        if list[questID] then
            list[questID] = nil
            Save(plugin, list)
        end
    end

    function Quests.Clear(plugin)
        plugin[field] = {}
        Save(plugin, plugin[field])
    end

    return table.freeze(Quests)
end

Addon.CompassQuestieHidden = QuestList("QuestieRemovedQuests", "compassQuestieHidden")
-- Quests whose QuestieDB hint the player asked for; none shows until then.
Addon.CompassQuestieHints = QuestList("QuestieHintQuests", "compassQuestieHints")
