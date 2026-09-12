local _, Addon = ...
local L = Addon.L
local Plugin = Addon.Controller
local MENU_LIMIT = 12
local CENTER_ANGLE = 15

function Plugin:FindCompassPoint(centered, query)
    local facing = centered and self:GetCompassFacing()
    if centered and not facing then
        return
    end
    local best, bestAngle
    for _, marker in ipairs(self.markers) do
        local angle = facing and marker.bearing and math.abs(Addon.Math:WrapDegrees(facing - marker.bearing)) or 0
        if
            marker.bearing
            and marker.distance
            and marker.key ~= self.navigationKey
            and (not query or marker.name:lower():find(query, 1, true))
            and marker.distance <= self.range
            and (not centered or (marker.renderShown and angle <= CENTER_ANGLE))
            and (
                not best
                or (centered and angle < bestAngle)
                or ((not centered or angle == bestAngle) and marker.distance < best.distance)
            )
        then
            best, bestAngle = marker, angle
        end
    end
    return best
end

function Plugin:TargetCompassPoint()
    if not self:IsActive() or self:IsProfileSuppressed() or self.inInstance or Addon.Services.IsEditMode() then
        return
    end
    local marker = self:FindCompassPoint(true)
    if marker then
        local destination = marker.destination
        local success, reason = self:SetWaypoint(destination.mapID, destination.x, destination.y, marker.name)
        if not success then
            print(reason)
        end
    end
end

function Plugin:ShowCompassNearby()
    if self.inInstance or Addon.Services.IsEditMode() then
        return
    end
    local markers = {}
    for _, marker in ipairs(self.markers) do
        if marker.distance and marker.distance <= self.range and marker.key ~= self.navigationKey then
            markers[#markers + 1] = marker
        end
    end
    table.sort(markers, function(a, b)
        if a.distance ~= b.distance then
            return a.distance < b.distance
        end
        return a.key < b.key
    end)
    MenuUtil.CreateContextMenu(self.frame, function(_, root)
        root:CreateTitle(L.PLU_COMPASS_NEARBY)
        for index = 1, math.min(MENU_LIMIT, #markers) do
            local marker = markers[index]
            root:CreateButton(
                L.PLU_COMPASS_DETAIL_F:format(marker.name, self:FormatCompassDistance(marker.distance)),
                function()
                    local destination = marker.destination
                    local success, reason =
                        self:SetWaypoint(destination.mapID, destination.x, destination.y, marker.name)
                    if not success then
                        print(reason)
                    end
                end
            )
        end
        if #markers == 0 then
            root:CreateTitle(L.CMD_COMPASS_NO_MATCH)
        end
    end)
end

function Plugin:HandleCompassPointCommand(command, argument)
    if command == "nearby" then
        self:ShowCompassNearby()
    elseif command == "target" then
        self:TargetCompassPoint()
    elseif command == "nearest" then
        local marker = self:FindCompassPoint(false, argument ~= "" and argument:lower() or nil)
        if marker then
            local destination = marker.destination
            local success, reason = self:SetWaypoint(destination.mapID, destination.x, destination.y, marker.name)
            print(success and L.CMD_COMPASS_SET or reason)
        else
            print(L.CMD_COMPASS_NO_MATCH)
        end
    else
        return false
    end
    return true
end

if not Addon.incompatibleOrbit then
    _G.BINDING_NAME_ORBIT_COMPASS_TARGET = L.PLU_COMPASS_TARGET_BINDING
end
