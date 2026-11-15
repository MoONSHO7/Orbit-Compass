local _, Addon = ...
local STORE_KEY = "QuestieRemovedQuests"
local Hidden = {}

-- The quests a player removed from the host's map stay with the character in the host plugin's store. Standalone
-- Compass has no such store and no map to remove from, so its list stays empty.
local function List(plugin)
    local list = plugin.compassQuestieHidden
    if not list then
        list = {}
        local stored = plugin.GetCharData and plugin:GetCharData(STORE_KEY)
        if type(stored) == "table" then
            for questID in pairs(stored) do
                if type(questID) == "number" then
                    list[questID] = true
                end
            end
        end
        plugin.compassQuestieHidden = list
    end
    return list
end

local function Save(plugin, list)
    if plugin.SetCharData then
        local stored = {}
        for questID in pairs(list) do
            stored[questID] = true
        end
        plugin:SetCharData(STORE_KEY, next(stored) and stored or nil)
    end
end

function Hidden.Has(plugin, questID)
    return List(plugin)[questID] == true
end

function Hidden.Count(plugin)
    local count = 0
    for _ in pairs(List(plugin)) do
        count = count + 1
    end
    return count
end

function Hidden.Add(plugin, questID)
    local list = List(plugin)
    if not list[questID] then
        list[questID] = true
        Save(plugin, list)
    end
end

function Hidden.Clear(plugin)
    plugin.compassQuestieHidden = {}
    Save(plugin, plugin.compassQuestieHidden)
end

Addon.CompassQuestieHidden = table.freeze(Hidden)
