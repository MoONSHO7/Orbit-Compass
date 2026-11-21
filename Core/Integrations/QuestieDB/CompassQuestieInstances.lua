local _, Addon = ...
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local DUNGEON_CATEGORY, MAX_ACTIVITIES = 2, 512
-- Forever's own group finder lists raids here (LFGVanilla_Constants.lua's LFGLISTING_RAID_CATEGORY_ID).
local RAID_CATEGORY = 114
local Instances = {}

local function ID(value)
    value = Number(value)
    return value and value > 0 and value % 1 == 0 and value or nil
end

-- A dungeon spans every normal activity (wing) on its map; a raid's 40- and 20-player difficulties need not count as
-- normal, and a map with a dungeon activity stays a dungeon, as Forever also lists raid versions of a few dungeons.
local function ReadCategory(result, category, raid)
    local list = Readable(C_LFGList.GetAvailableActivities(category))
    if type(list) ~= "table" or #list > MAX_ACTIVITIES then
        return
    end
    for _, rawID in ipairs(list) do
        local activityID = ID(rawID)
        local info = activityID and Readable(C_LFGList.GetActivityInfoTable(activityID))
        local mapID = type(info) == "table" and ID(info.mapID)
        local low, high = mapID and Number(info.minLevelSuggestion), mapID and Number(info.maxLevelSuggestion)
        local previous = mapID and result[mapID]
        if
            mapID
            and Number(info.categoryID) == category
            and (raid or Readable(info.isNormalActivity) == true)
            and low
            and high
            and low > 0
            and high >= low
            and (not previous or previous.raid == raid)
        then
            result[mapID] = {
                minLevel = previous and math.min(previous.minLevel, low) or low,
                maxLevel = previous and math.max(previous.maxLevel, high) or high,
                raid = raid,
            }
        end
    end
end

-- Each instance map's suggested levels from the group finder, read once a collection; the first read asks the client
-- for the list, whose answer refreshes the source.
function Instances.Read(plugin)
    local result = {}
    if not plugin.compassInstanceLevelsRequested then
        plugin.compassInstanceLevelsRequested = true
        C_LFGList.RequestAvailableActivities()
    end
    ReadCategory(result, DUNGEON_CATEGORY, false)
    ReadCategory(result, RAID_CATEGORY, true)
    return result
end

Addon.CompassQuestieInstances = table.freeze(Instances)
