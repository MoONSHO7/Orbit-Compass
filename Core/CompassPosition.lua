local _, Addon = ...
local Plugin = Addon.Controller
local Utils = Addon.SourceUtils
local Number, ReadPosition = Utils.Number, Utils.ReadPosition
local POSITION_SYNC_INTERVAL = 1

function Plugin:ReadCompassPosition()
    local north, west, _, instance = UnitPosition("player")
    north, west, instance = Number(north), Number(west), Number(instance)
    if not north or not west or not instance then
        self.positionInstance = nil
        return ReadPosition(C_Map.GetPlayerMapPosition(self.mapID, "player"))
    end
    if self.positionInstance ~= instance or self.discoveryClock >= self.positionNextSync then
        if Number(C_Map.GetBestMapForUnit("player")) ~= self.mapID then
            self.discoveryDirty = true
            return
        end
        local x, y = ReadPosition(C_Map.GetPlayerMapPosition(self.mapID, "player"))
        self.positionNextSync = self.discoveryClock + POSITION_SYNC_INTERVAL
        if x and y then
            self.positionInstance = instance
            self.positionMapX, self.positionMapY = x, y
            self.positionNorth, self.positionWest = north, west
        elseif self.positionInstance ~= instance then
            return
        end
    end
    if self.positionMapX and self.positionMapY then
        -- UnitPosition axes run north/west; periodic map samples reconcile phases and map availability.
        return self.positionMapX - (west - self.positionWest) / self.mapWidth,
            self.positionMapY - (north - self.positionNorth) / self.mapHeight
    end
end
