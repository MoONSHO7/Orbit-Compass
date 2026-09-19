local _, Addon = ...
local Utils = Addon.SourceUtils
local MAX_ANCESTORS = 64
local Scope = {}

local function Ancestor(start, rootType)
    local mapID, root, visited = Utils.Number(start), nil, {}
    for _ = 1, MAX_ANCESTORS do
        if mapID == 0 then
            return root
        end
        if not mapID or visited[mapID] then
            return
        end
        visited[mapID] = true
        local info = Utils.Readable(C_Map.GetMapInfo(mapID))
        if type(info) ~= "table" then
            return
        end
        if Utils.Number(info.mapType) == rootType then
            root = mapID
        end
        mapID = Utils.Number(info.parentMapID)
    end
end

function Scope.Resolve(rootType, previous)
    local root = Ancestor(C_Map.GetBestMapForUnit("player"), rootType)
    if not root and C_Map.GetFallbackWorldMapID then
        root = Ancestor(C_Map.GetFallbackWorldMapID(), rootType)
    end
    if not root and previous then
        root = Ancestor(previous, rootType)
    end
    return root
end

Addon.MapScope = table.freeze(Scope)
