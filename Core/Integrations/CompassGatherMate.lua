local _, Addon = ...
local Plugin = Addon.Controller
local C = Addon.Constants
local L = Addon.L
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local REFRESH_INTERVAL = 30
local ICON_SCALE = 0.6
local MESSAGES = {
    "GatherMate2NodeAdded",
    "GatherMate2NodeDeleted",
    "GatherMate2ConfigChanged",
    "GatherMate2Cleanup",
}

local function Provider()
    local provider = Readable(_G.GatherMate2)
    if type(provider) ~= "table" then
        return
    end
    for _, method in ipairs({ "GetNodesForZone", "DecodeLoc", "GetNameForNode", "IsEnabled" }) do
        if type(Readable(provider[method])) ~= "function" then
            return
        end
    end
    return provider
end

local function Snapshot(provider, mapID, nodeType)
    local records = {}
    if Readable(provider:IsEnabled()) ~= true then
        return records
    end
    local textures = Readable(provider.nodeTextures)
    textures = type(textures) == "table" and Readable(textures[nodeType]) or nil
    for coord, nodeID in provider:GetNodesForZone(mapID, nodeType) do
        coord, nodeID = Number(coord), Number(nodeID)
        if coord and nodeID and coord >= 0 and coord % 1 == 0 then
            local x, y = provider:DecodeLoc(coord)
            x, y = Number(x), Number(y)
            local name = Readable(provider:GetNameForNode(nodeType, nodeID))
            local texture = type(textures) == "table" and Readable(textures[nodeID]) or nil
            if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 and type(name) == "string" and name ~= "" then
                records[#records + 1] = {
                    coord = coord,
                    nodeID = nodeID,
                    x = x,
                    y = y,
                    name = name,
                    texture = (type(texture) == "string" or type(texture) == "number") and texture or nil,
                }
            end
        end
    end
    return records
end

function Plugin:CollectCompassGatherMate(markers)
    local provider = Provider()
    if not provider or not self.showGatherMate then
        return REFRESH_INTERVAL
    end
    local types, visible = Readable(provider.db_types), Readable(provider.Visible)
    if type(types) ~= "table" or type(visible) ~= "table" then
        return REFRESH_INTERVAL
    end
    for _, nodeType in pairs(types) do
        nodeType = Readable(nodeType)
        if type(nodeType) == "string" and Readable(visible[nodeType]) == true then
            -- Finish the external iterator before yielding; database updates can invalidate its cursor.
            local ok, records = pcall(Snapshot, provider, self.mapID, nodeType)
            if not ok then
                error(records, 0)
            end
            for _, record in ipairs(records) do
                local key = "gathermate:"
                    .. self.mapID
                    .. ":"
                    .. nodeType
                    .. ":"
                    .. record.coord
                    .. ":"
                    .. record.nodeID
                local marker = Utils.AddMarker(
                    self,
                    markers,
                    key,
                    record,
                    record.name,
                    C.FALLBACK_ATLAS,
                    C.POI_PRIORITY,
                    "gathermate:" .. nodeType
                )
                marker.sizeScale = ICON_SCALE
                marker.texture = record.texture
                marker.description = L.PLU_COMPASS_GATHERMATE_LOCATION
                self:CompassDiscoveryCheckpoint()
            end
        end
    end
    return REFRESH_INTERVAL
end

function Plugin:ConnectCompassGatherMate()
    if not self.compassIntegrationsEnabled or self.compassGatherMateReceiver then
        return
    end
    local provider = Provider()
    if
        not provider
        or type(provider.RegisterMessage) ~= "function"
        or type(provider.UnregisterAllMessages) ~= "function"
    then
        return
    end
    local receiver = {}
    self.compassGatherMateReceiver, self.compassGatherMateProvider = receiver, provider
    local changed = Addon.LibOrbitUI.Callbacks:Wrap(function(plugin)
        if plugin.compassIntegrationsEnabled then
            plugin:InvalidateCompassSourceSettings("gathermate")
        end
    end, "Compass.GatherMate")
    for _, message in ipairs(MESSAGES) do
        provider.RegisterMessage(receiver, message, function()
            changed(self)
        end)
    end
    self:InvalidateCompassSourceSettings("gathermate")
end

function Plugin:DisconnectCompassGatherMate()
    if self.compassGatherMateReceiver then
        self.compassGatherMateProvider.UnregisterAllMessages(self.compassGatherMateReceiver)
        self.compassGatherMateReceiver, self.compassGatherMateProvider = nil, nil
    end
end
