local _, Addon = ...
local Plugin = Addon.Controller
local Sources = Addon.LandmarkSources
local Duplicates = Addon.LandmarkDuplicates
local QueryIndex = Addon.LandmarkQueryIndex
local Fold, Words, AddNameFields = Addon.Text.Fold, Addon.Text.Words, Addon.Text.AddNameFields
local MAP_DEPTH = Sources.MapDepth
local PIN_KEYS = Sources.PinKeys
local COLLECT_PHASE = "Compass.Landmarks.Collect"

local CONTINENT_MAP = Enum.UIMapType.Continent
local ZONE_MAP = Enum.UIMapType.Zone
local MICRO_MAP = Enum.UIMapType.Micro
-- Zones outrank micro maps, which outrank continents, so later passes skip reads that cannot win.
local COLLECT_PASSES = { ZONE_MAP, MICRO_MAP, CONTINENT_MAP }

local Build = {}

local function Finalize(landmark, placeWords)
    local place = (landmark.zone or "") .. " " .. (landmark.continent or "")
    local words = placeWords[place]
    if not words then
        words = Words(Fold(place))
        table.freeze(words)
        placeWords[place] = words
    end
    landmark.placeWords = words
    return table.freeze(AddNameFields(landmark, landmark.name))
end

local function Collect(catalog, target, checkpoint, phase)
    local placeWords = {}
    -- Collection is not in map order, so an equal rank still goes to the map the native list returned first.
    local owners, mapIndex = {}, 0
    local function Outranks(key, rank)
        local current = target.ranks[key]
        return not current or rank > current or (rank == current and mapIndex < owners[key])
    end
    local function Wins(prefix, id, rank)
        return Outranks(prefix .. id, rank)
    end
    local function Add(landmark, rank)
        if not landmark then
            return
        end
        local key = landmark.key
        local position = target.positions[key]
        if position and not Outranks(key, rank) then
            return
        end
        landmark = Finalize(landmark, placeWords)
        if not position then
            target.entries[#target.entries + 1] = landmark
            target.positions[key], target.ranks[key] = #target.entries, rank
        else
            target.entries[position], target.ranks[key] = landmark, rank
        end
        owners[key] = mapIndex
        if target == catalog then
            catalog.revision = catalog.revision + 1
        end
    end
    local static = catalog.static or Sources.NewStaticLayer()
    catalog.static = static
    local maps, order = Sources.ReadHierarchy(catalog.rootID, static, checkpoint, phase)
    if not maps then
        return
    end
    local function Lookup(mapID)
        return maps[mapID]
    end
    local continents = {}
    local function Continent(mapID)
        local name = continents[mapID]
        if name == nil then
            name = Sources.ContinentName(mapID, Lookup) or false
            continents[mapID] = name
        end
        return name or nil
    end
    checkpoint()
    local areas = {}
    phase(COLLECT_PHASE)
    for index, mapID in ipairs(order) do
        local details = maps[mapID]
        if MAP_DEPTH[details.mapType] and details.parentMapID then
            mapIndex = index
            local parent = maps[details.parentMapID]
            Sources.CollectArea(
                details,
                { zone = parent and parent.name, continent = Continent(mapID) },
                Add,
                areas,
                static
            )
        end
        checkpoint()
    end
    for _, mapType in ipairs(COLLECT_PASSES) do
        local depth = MAP_DEPTH[mapType]
        for index, mapID in ipairs(order) do
            local details = maps[mapID]
            if details.mapType == mapType and details.parentMapID then
                mapIndex = index
                local place = { zone = details.name, continent = Continent(mapID) }
                Sources.CollectMap(mapID, place, depth, Add, checkpoint, Wins, static)
            end
            checkpoint()
        end
    end
    return maps
end

function Build.Run(catalog, target, setPhase)
    local incomplete = false
    local function Phase(phase)
        setPhase(catalog, phase)
    end
    local function Checkpoint(pending)
        incomplete = incomplete or pending == true
        if debugprofilestop() >= catalog.deadline then
            coroutine.yield()
        end
    end
    local maps = Collect(catalog, target, Checkpoint, Phase)
    if not maps then
        return false
    end
    local entries, positions, ranks = Duplicates.Remove(target, maps, Checkpoint, Phase)
    local queryIndex
    if not incomplete or target == catalog then
        queryIndex = QueryIndex.Build(entries, Checkpoint, Phase)
    end
    target.entries, target.positions, target.ranks, target.queryIndex = entries, positions, ranks, queryIndex
    return incomplete and "incomplete" or true
end

function Plugin:FindCompassLandmarkOnMap(mapID, pinType, id)
    local place = Sources.ReadMapPlace(mapID)
    local key = PIN_KEYS[pinType] and PIN_KEYS[pinType] .. id
    local found
    local function Add(landmark)
        if landmark and landmark.key == key then
            found = Finalize(landmark, {})
        end
    end
    local function Wanted(prefix, candidate)
        return prefix .. candidate == key
    end
    Sources.CollectPin(mapID, pinType, place, Add, Wanted)
    return found
end

Addon.LandmarkBuild = table.freeze(Build)
