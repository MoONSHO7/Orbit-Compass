local _, Addon = ...
local MAP_DEPTH = Addon.LandmarkMaps.Depth
local Utils = Addon.SourceUtils
local Number = Utils.Number

local Duplicates = {}
local CONTINENT_DEPTH = MAP_DEPTH[Enum.UIMapType.Continent]
local DUPLICATE_YARDS = 100
local CELL_YARDS = DUPLICATE_YARDS / 2
local CELL_RANGE = DUPLICATE_YARDS / CELL_YARDS
local MIN_GRID_GROUP = 16
local PHASE = {
    DUPLICATE_GROUPS = "Compass.Landmarks.Duplicates.Group",
    DUPLICATE_COMPARE = "Compass.Landmarks.Duplicates.Compare",
    DUPLICATE_COMPACT = "Compass.Landmarks.Duplicates.Compact",
}

local function IsAncestor(maps, ancestorID, mapID)
    local visited = {}
    local details = maps[mapID]
    while details and details.parentMapID and not visited[details.mapID] do
        visited[details.mapID] = true
        if details.parentMapID == ancestorID then
            return true
        end
        details = maps[details.parentMapID]
    end
    return false
end

local function MapDepth(maps, mapID)
    local details = maps[mapID]
    return details and MAP_DEPTH[details.mapType] or 0
end

local function Project(landmark)
    local instance, position = C_Map.GetWorldPosFromMapPos(landmark.mapID, CreateVector2D(landmark.x, landmark.y))
    local x, y = Utils.ReadPosition(position)
    return { instance = Number(instance), x = x, y = y }
end

local function WorldPosition(landmark, cache)
    local cached = cache[landmark]
    if not cached then
        cached = Project(landmark)
        cache[landmark] = cached
    end
    return cached
end

local function InRange(a, b)
    local east, north = a.x - b.x, a.y - b.y
    return east * east + north * north <= DUPLICATE_YARDS * DUPLICATE_YARDS
end

local function SamePlace(left, right, cache)
    local a, b = WorldPosition(left, cache), WorldPosition(right, cache)
    return a.instance and a.instance == b.instance and a.x and a.y and b.x and b.y and InRange(a, b)
end

local function HigherRank(keep, drop, ranks)
    local keepRank, dropRank = ranks[keep.key], ranks[drop.key]
    return keepRank > dropRank or (keepRank == dropRank and keep.key < drop.key)
end

-- Parent and continent maps repeat a place under other POI IDs; only the deepest map's copy routes correctly.
local function Supersedes(keep, drop, ranks, maps, cache)
    if IsAncestor(maps, drop.mapID, keep.mapID) then
        return true
    end
    local keepDepth, dropDepth = MapDepth(maps, keep.mapID), MapDepth(maps, drop.mapID)
    if keepDepth > dropDepth and dropDepth == CONTINENT_DEPTH then
        return true
    elseif keepDepth < dropDepth or IsAncestor(maps, keep.mapID, drop.mapID) or not SamePlace(keep, drop, cache) then
        return false
    end
    return HigherRank(keep, drop, ranks)
end

local function MarkSmallGroup(group, ranks, maps, removed, checkpoint)
    local cache = {}
    for _, candidate in ipairs(group) do
        for _, other in ipairs(group) do
            if other ~= candidate and Supersedes(other, candidate, ranks, maps, cache) then
                removed[candidate.key] = true
                checkpoint()
                break
            end
            checkpoint()
        end
        checkpoint()
    end
end

local function IndexAncestors(group, maps, checkpoint)
    local ancestorsByMap, counts, deepest = {}, {}, 0
    for _, landmark in ipairs(group) do
        local ancestors = ancestorsByMap[landmark.mapID]
        if not ancestors then
            ancestors = {}
            local visited, details = {}, maps[landmark.mapID]
            while details and details.parentMapID and not visited[details.mapID] do
                visited[details.mapID] = true
                ancestors[details.parentMapID] = true
                details = maps[details.parentMapID]
                checkpoint()
            end
            ancestorsByMap[landmark.mapID] = ancestors
        end
        for ancestorID in pairs(ancestors) do
            counts[ancestorID] = (counts[ancestorID] or 0) + 1
            checkpoint()
        end
        deepest = math.max(deepest, MapDepth(maps, landmark.mapID))
        checkpoint()
    end
    return ancestorsByMap, counts, deepest
end

local function IndexPositions(group, ranks, maps, checkpoint)
    local grid, points = {}, {}
    for _, landmark in ipairs(group) do
        local point = Project(landmark)
        checkpoint()
        if point.instance and point.x and point.y then
            point.landmark, point.depth = landmark, MapDepth(maps, landmark.mapID)
            point.cellX, point.cellY = math.floor(point.x / CELL_YARDS), math.floor(point.y / CELL_YARDS)
            local world = grid[point.instance] or {}
            grid[point.instance] = world
            local column = world[point.cellX] or {}
            world[point.cellX] = column
            local cell = column[point.cellY] or {}
            column[point.cellY] = cell
            local bucket = cell[point.depth]
            if bucket then
                bucket.minX, bucket.maxX = math.min(bucket.minX, point.x), math.max(bucket.maxX, point.x)
                bucket.minY, bucket.maxY = math.min(bucket.minY, point.y), math.max(bucket.maxY, point.y)
            else
                bucket = { minX = point.x, maxX = point.x, minY = point.y, maxY = point.y }
                cell[point.depth] = bucket
            end
            bucket[#bucket + 1] = point
            if not bucket.best or HigherRank(landmark, bucket.best.landmark, ranks) then
                bucket.best = point
            end
            points[#points + 1] = point
        end
        checkpoint()
    end
    return grid, points
end

local function CanReach(other, candidate, ancestors)
    return not ancestors[other.landmark.mapID] and InRange(other, candidate)
end

local function BucketInRange(bucket, candidate)
    local east = math.max(bucket.minX - candidate.x, candidate.x - bucket.maxX, 0)
    local north = math.max(bucket.minY - candidate.y, candidate.y - bucket.maxY, 0)
    return east * east + north * north <= DUPLICATE_YARDS * DUPLICATE_YARDS
end

local function CellSupersedes(cell, candidate, ranks, ancestors, checkpoint)
    for depth, bucket in pairs(cell) do
        local best = bucket.best
        if depth >= candidate.depth and HigherRank(best.landmark, candidate.landmark, ranks) then
            if CanReach(best, candidate, ancestors) then
                return true
            end
            if BucketInRange(bucket, candidate) then
                for _, other in ipairs(bucket) do
                    if
                        other ~= best
                        and HigherRank(other.landmark, candidate.landmark, ranks)
                        and CanReach(other, candidate, ancestors)
                    then
                        return true
                    end
                    checkpoint()
                end
            end
        end
    end
    return false
end

local function HasNearbyWinner(world, candidate, ranks, ancestors, checkpoint)
    for x = -CELL_RANGE, CELL_RANGE do
        local column = world[candidate.cellX + x]
        if column then
            for y = -CELL_RANGE, CELL_RANGE do
                local cell = column[candidate.cellY + y]
                if cell and CellSupersedes(cell, candidate, ranks, ancestors, checkpoint) then
                    return true
                end
            end
        end
    end
    return false
end

local function MarkGridGroup(group, ranks, maps, removed, checkpoint)
    local ancestorsByMap, counts, deepest = IndexAncestors(group, maps, checkpoint)
    local survivors = 0
    for _, landmark in ipairs(group) do
        local mapID = landmark.mapID
        local ownAncestor = ancestorsByMap[mapID][mapID] and 1 or 0
        if
            (counts[mapID] or 0) > ownAncestor
            or (MapDepth(maps, mapID) == CONTINENT_DEPTH and deepest > CONTINENT_DEPTH)
        then
            removed[landmark.key] = true
        else
            survivors = survivors + 1
        end
        checkpoint()
    end
    if survivors == 0 then
        return
    end
    -- Even a copy marked for removal can suppress a different copy. The search indexes the entire input group.
    local grid, points = IndexPositions(group, ranks, maps, checkpoint)
    for _, candidate in ipairs(points) do
        local landmark = candidate.landmark
        if not removed[landmark.key] then
            if
                HasNearbyWinner(grid[candidate.instance], candidate, ranks, ancestorsByMap[landmark.mapID], checkpoint)
            then
                removed[landmark.key] = true
            end
        end
        checkpoint()
    end
end

function Duplicates.Remove(target, maps, checkpoint, phase)
    phase(PHASE.DUPLICATE_GROUPS)
    local groups = {}
    for _, landmark in ipairs(target.entries) do
        if not landmark.questID then
            local group = groups[landmark.name]
            if group then
                group[#group + 1] = landmark
            else
                groups[landmark.name] = { landmark }
            end
        end
        checkpoint()
    end
    local removed = {}
    phase(PHASE.DUPLICATE_COMPARE)
    for _, group in pairs(groups) do
        if #group >= MIN_GRID_GROUP then
            MarkGridGroup(group, target.ranks, maps, removed, checkpoint)
        elseif #group > 1 then
            MarkSmallGroup(group, target.ranks, maps, removed, checkpoint)
        end
        checkpoint()
    end
    local entries, positions, ranks = {}, {}, {}
    phase(PHASE.DUPLICATE_COMPACT)
    for _, landmark in ipairs(target.entries) do
        if not removed[landmark.key] then
            entries[#entries + 1] = landmark
            positions[landmark.key], ranks[landmark.key] = #entries, target.ranks[landmark.key]
        end
        checkpoint()
    end
    return entries, positions, ranks
end

Addon.LandmarkDuplicates = table.freeze(Duplicates)
