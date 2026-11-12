local _, Addon = ...
local Readable, Number = Addon.SourceUtils.Readable, Addon.SourceUtils.Number
local REQUIRED_CONTRACT = 4
local PERCENT = 100
local BUILD_BUDGET_MS = 0.5
local NPC_SLOT, OBJECT_SLOT = 1, 2
-- QuestieDB service flag name and the Enum.MinimapTrackingFilter field whose icon and label present it.
local SERVICES = {
    { flag = "INNKEEPER", filter = "Innkeeper" },
    { flag = "REPAIR", filter = "Repair" },
    { flag = "BANKER", filter = "Banker" },
    { flag = "AUCTIONEER", filter = "Auctioneer" },
    { flag = "STABLEMASTER", filter = "Stablemaster" },
}
local NPC_GETTERS = { "GetAllIds", "npcFlags", "spawns", "friendlyToFaction", "name" }
local OBJECT_GETTERS = { "spawns", "name" }
local QUEST_GETTERS = { "GetAllIds", "GetAll", "startedBy", "name" }
local Index = {}

-- QuestieDB masks can exceed 32 bits, so single-bit membership uses arithmetic rather than the 32-bit bit library.
function Index.HasBit(mask, value)
    return value ~= nil and value > 0 and math.floor(mask / value) % 2 == 1
end

local function HasFunctions(entity, names)
    if type(entity) ~= "table" then
        return false
    end
    for _, name in ipairs(names) do
        if type(entity[name]) ~= "function" then
            return false
        end
    end
    return true
end

-- The installed QuestieDB when it meets contract 4 (NPC flags and class keys) and exposes every read used here.
function Index.Provider()
    local lib = Readable(_G.LibQuestieDB)
    if
        type(lib) ~= "table"
        or type(lib.RequireContract) ~= "function"
        or lib.RequireContract(REQUIRED_CONTRACT) ~= true
    then
        return
    end
    local enum, support = lib.Enum, lib.Support
    if
        not HasFunctions(lib.Npc, NPC_GETTERS)
        or not HasFunctions(lib.Object, OBJECT_GETTERS)
        or not HasFunctions(lib.Quest, QUEST_GETTERS)
        or type(support) ~= "table"
        or type(support.Get) ~= "function"
        or type(enum) ~= "table"
        or type(enum.npcFlags) ~= "table"
        or type(enum.classKeys) ~= "table"
        or type(enum.raceMaskById) ~= "table"
    then
        return
    end
    return lib
end

-- QuestieDB publishes its area-to-UiMap table as Lua source for consumers to load; it runs without any environment.
local function AreaMaps(zoneDB)
    local private = type(zoneDB) == "table" and zoneDB.private
    local source = type(private) == "table" and private.areaIdToUiMapId
    if type(source) ~= "string" then
        return
    end
    local chunk = loadstring(source)
    if not chunk then
        return
    end
    setfenv(chunk, {})
    local ok, maps = pcall(chunk)
    return ok and type(maps) == "table" and maps or nil
end

local function Bucket(build, mapID, kind)
    local entry = build.byMap[mapID]
    if not entry then
        entry = { givers = {}, services = {}, entrances = {} }
        build.byMap[mapID] = entry
    end
    return entry[kind]
end

-- `ordinals` numbers one record's points per map, so a marker key never depends on other records' spawns.
local function AddPoint(build, areaID, x, y, kind, record, ordinals)
    local mapID = Number(build.areaMaps[areaID])
    x, y = Number(x), Number(y)
    if mapID and mapID > 0 and x and y and x >= 0 and x <= PERCENT and y >= 0 and y <= PERCENT then
        local list = Bucket(build, mapID, kind)
        ordinals[mapID] = (ordinals[mapID] or 0) + 1
        list[#list + 1] = { record = record, x = x / PERCENT, y = y / PERCENT, ordinal = ordinals[mapID] }
    end
end

local function AddSpawns(build, spawns, kind, record)
    local ordinals = {}
    for areaID, points in pairs(spawns) do
        if type(points) == "table" then
            for _, point in ipairs(points) do
                if type(point) == "table" then
                    AddPoint(build, areaID, point[1], point[2], kind, record, ordinals)
                end
            end
        end
    end
end

local function AddStarters(starters, owners, questID)
    if type(owners) ~= "table" then
        return
    end
    for _, owner in ipairs(owners) do
        owner = Number(owner)
        if owner then
            local quests = starters[owner]
            if not quests then
                quests = {}
                starters[owner] = quests
            end
            quests[#quests + 1] = questID
        end
    end
end

-- Givers come from each quest's starters, so the 6.6k-row object table never has to be swept or cached.
local function IndexQuest(build, quest, id)
    local startedBy = quest.startedBy(id)
    if type(startedBy) == "table" then
        AddStarters(build.npcQuests, startedBy[NPC_SLOT], id)
        AddStarters(build.objectQuests, startedBy[OBJECT_SLOT], id)
    end
end

local function ServiceFilters(build, flags)
    local found
    for _, service in ipairs(build.services) do
        if Index.HasBit(flags, service.bit) then
            found = found or {}
            found[#found + 1] = service.filter
        end
    end
    return found
end

local function IndexNpc(build, npc, id)
    local quests = build.npcQuests[id]
    local flags = Number(npc.npcFlags(id)) or 0
    local services = flags ~= 0 and ServiceFilters(build, flags) or nil
    if not quests and not services then
        return
    end
    local spawns = npc.spawns(id)
    local faction = npc.friendlyToFaction(id)
    if type(spawns) ~= "table" or type(faction) ~= "string" then
        return
    end
    local record = { entity = "npc", id = id, quests = quests, services = services, faction = faction }
    if quests then
        AddSpawns(build, spawns, "givers", record)
    end
    if services then
        AddSpawns(build, spawns, "services", record)
    end
end

local function IndexObject(build, object, id)
    local spawns = object.spawns(id)
    if type(spawns) == "table" then
        AddSpawns(build, spawns, "givers", { entity = "object", id = id, quests = build.objectQuests[id] })
    end
end

-- An instance counts only when this client names its map; QuestieDB's table also carries later expansions' entrances.
local function IndexEntrances(build, zoneDB)
    local private = zoneDB.private
    local dungeons = type(private) == "table" and private.dungeons
    local instances = zoneDB.instanceIdToAreaId
    if type(dungeons) ~= "table" or type(instances) ~= "table" then
        return
    end
    for instanceID, areaID in pairs(instances) do
        instanceID = Number(instanceID)
        local name = instanceID and Readable(GetRealZoneText(instanceID))
        local entry = dungeons[areaID]
        local locations = type(entry) == "table" and entry[4]
        if type(name) == "string" and name ~= "" and type(locations) == "table" then
            local record, ordinals = { entity = "instance", id = instanceID, name = name }, {}
            for _, location in ipairs(locations) do
                if type(location) == "table" then
                    AddPoint(build, location[1], location[2], location[3], "entrances", record, ordinals)
                end
            end
        end
    end
end

local function StartBuild(lib)
    local zoneDB = lib.Support.Get("ZoneDB")
    local areaMaps = AreaMaps(zoneDB)
    if not areaMaps then
        return
    end
    local services = {}
    for _, service in ipairs(SERVICES) do
        local value = Number(lib.Enum.npcFlags[service.flag])
        if value and value > 0 then
            services[#services + 1] = { bit = value, filter = service.filter }
        end
    end
    return {
        lib = lib,
        zoneDB = zoneDB,
        areaMaps = areaMaps,
        services = services,
        byMap = {},
        npcQuests = {},
        objectQuests = {},
        questIDs = lib.Quest.GetAllIds(),
        npcIDs = lib.Npc.GetAllIds(),
        questCursor = 0,
        npcCursor = 0,
    }
end

-- Advances the build within this frame's budget; true once the index is published.
local function Step(plugin)
    local build = plugin.compassQuestieBuild
    local lib, deadline = build.lib, debugprofilestop() + BUILD_BUDGET_MS
    while build.questCursor < #build.questIDs do
        build.questCursor = build.questCursor + 1
        IndexQuest(build, lib.Quest, build.questIDs[build.questCursor])
        if debugprofilestop() >= deadline then
            return false
        end
    end
    while build.npcCursor < #build.npcIDs do
        build.npcCursor = build.npcCursor + 1
        IndexNpc(build, lib.Npc, build.npcIDs[build.npcCursor])
        if debugprofilestop() >= deadline then
            return false
        end
    end
    for objectID in pairs(build.objectQuests) do
        IndexObject(build, lib.Object, objectID)
    end
    IndexEntrances(build, build.zoneDB)
    plugin.compassQuestieIndex = { lib = lib, byMap = build.byMap, quests = {} }
    plugin.compassQuestieBuild = nil
    return true
end

local function Drive(plugin)
    -- One protected step per frame: a failing build stops for the session instead of erroring every frame.
    local ok, done = pcall(Step, plugin)
    if ok and not done then
        return
    end
    plugin.compassQuestieDriver:SetScript("OnUpdate", nil)
    plugin.compassQuestieDriving = false
    if not ok then
        local build = plugin.compassQuestieBuild
        plugin.compassQuestieFailed, plugin.compassQuestieBuild = build and build.lib, nil
        geterrorhandler()(done)
        return
    end
    plugin:InvalidateCompassSourceSettings("questie", true)
end

-- The published index; otherwise nil plus whether one is still building in its own per-frame budget, outside
-- discovery's single job slot.
function Index.Request(plugin, lib)
    local index = plugin.compassQuestieIndex
    if index and index.lib == lib then
        return index
    end
    if plugin.compassQuestieFailed == lib then
        return nil, false
    end
    local build = plugin.compassQuestieBuild
    if not build or build.lib ~= lib then
        build = StartBuild(lib)
        if not build then
            return nil, false
        end
        plugin.compassQuestieBuild = build
    end
    local driver = plugin.compassQuestieDriver
    if not driver then
        driver = CreateFrame("Frame")
        plugin.compassQuestieDriver = driver
    end
    if not plugin.compassQuestieDriving then
        plugin.compassQuestieDriving = true
        driver:SetScript("OnUpdate", function()
            Drive(plugin)
        end)
    end
    return nil, true
end

-- Pauses an unfinished build while Compass is disabled; its progress resumes on the next request.
function Index.Stop(plugin)
    if plugin.compassQuestieDriver then
        plugin.compassQuestieDriver:SetScript("OnUpdate", nil)
        plugin.compassQuestieDriving = false
    end
end

Addon.CompassQuestieIndex = table.freeze(Index)
