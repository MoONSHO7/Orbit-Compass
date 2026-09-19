local _, Addon = ...
local C = Addon.Constants
local Pixel = Addon.Services.pixel
local Plugin = Addon.Controller
local GATHERMATE_KIND_PREFIX = "gathermate:"

local function LeftBefore(a, b)
    if a.projectedBelowLine ~= b.projectedBelowLine then
        return not a.projectedBelowLine
    end
    if a.projectedLeftPx ~= b.projectedLeftPx then
        return a.projectedLeftPx < b.projectedLeftPx
    end
    return a.key < b.key
end

local function NearBefore(a, b)
    if a.distanceSquared ~= b.distanceSquared then
        return a.distanceSquared < b.distanceSquared
    end
    return a.key < b.key
end

local function RefreshNearOrder(order, members, selection)
    local membershipChanged = #order ~= #selection
    if not membershipChanged then
        for _, marker in ipairs(order) do
            if not members[marker] then
                membershipChanged = true
                break
            end
        end
    end
    if membershipChanged then
        wipe(order)
        for index, marker in ipairs(selection) do
            order[index] = marker
        end
    end
    for index = 2, #order do
        if NearBefore(order[index], order[index - 1]) then
            table.sort(order, NearBefore)
            return true, membershipChanged
        end
    end
    return false, membershipChanged
end

function Plugin:LayoutCompassMarkerGroups(selection)
    local layout = self.artworkLayout
    local scale, centerX = layout.scale, layout.centerX
    local outline = Pixel:Multiple(C.MARKER_OUTLINE * 2, scale)
    local order, groups = self.markerGroupOrder, self.markerGroups
    local leftOrder, members = self.markerLeftOrder, self.markerGroupMembers
    wipe(leftOrder)
    wipe(members)
    for _, group in ipairs(groups) do
        wipe(group.markers)
    end
    for index, marker in ipairs(selection) do
        marker.projectedBelowLine = marker.kind:sub(1, #GATHERMATE_KIND_PREFIX) == GATHERMATE_KIND_PREFIX
        local distanceFraction = math.max(
            0,
            math.min(1, (marker.distance - C.MARKER_NEAR_DISTANCE) / (C.MARKER_FAR_DISTANCE - C.MARKER_NEAR_DISTANCE))
        )
        local distanceScale = C.MARKER_FAR_SCALE + (1 - distanceFraction) * (C.MARKER_NEAR_SCALE - C.MARKER_FAR_SCALE)
        marker.projectedIconSize = Pixel:Snap(self.iconSize * marker.sizeScale * distanceScale, scale)
        marker.projectedHitSize = marker.projectedIconSize + outline
        local left = Pixel:Snap(centerX + marker.projectedX - marker.projectedHitSize / 2, scale)
        marker.projectedLeft = left
        marker.projectedLeftPx = Pixel:ToCount(left, scale)
        marker.projectedRightPx = marker.projectedLeftPx + Pixel:ToCount(marker.projectedHitSize, scale)
        leftOrder[index] = marker
        members[marker] = true
    end
    table.sort(leftOrder, LeftBefore)
    local group, right, belowLine = 0, nil, nil
    for _, marker in ipairs(leftOrder) do
        if belowLine ~= marker.projectedBelowLine or not right or marker.projectedLeftPx >= right then
            group = group + 1
            right = marker.projectedRightPx
            groups[group] = groups[group] or { markers = {} }
        else
            right = math.max(right, marker.projectedRightPx)
        end
        marker.overlapGroup = groups[group]
        belowLine = marker.projectedBelowLine
    end
    local sorted, membershipChanged = RefreshNearOrder(order, members, selection)
    local profiler = Addon.Services.profiler
    if profiler and profiler.active then
        profiler:Count(self, sorted and "Groups/DepthSort" or "Groups/DepthSortSkipped")
        if membershipChanged then
            profiler:Count(self, "Groups/MembershipChanged")
        end
    end
    for index, marker in ipairs(order) do
        local record = marker.overlapGroup
        record.markers[#record.markers + 1] = marker
        marker.depthLevel = C.MARKER_BASE_LEVEL + #order - index
    end
end
