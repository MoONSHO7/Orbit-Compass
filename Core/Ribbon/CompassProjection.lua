local _, Addon = ...
local C = Addon.Constants
local CompassMath = Addon.Math
local Plugin = Addon.Controller

local function LimitTurn(delta, halfView, minimum, maximum)
    local leaving, entering = halfView - delta, -halfView - delta
    if leaving > C.HALF_TURN then
        leaving = leaving - C.FULL_TURN
    end
    if entering < -C.HALF_TURN then
        entering = entering + C.FULL_TURN
    end
    if leaving >= 0 then
        maximum = math.min(maximum, leaving)
    end
    if leaving <= 0 then
        minimum = math.max(minimum, leaving)
    end
    if entering >= 0 then
        maximum = math.min(maximum, entering)
    end
    if entering <= 0 then
        minimum = math.max(minimum, entering)
    end
    return minimum, maximum
end

local function ProjectSelection(plugin, facing, width)
    for _, marker in ipairs(plugin.selectedMarkers) do
        if not marker.bearing then
            return false
        end
        local x, alpha, delta = CompassMath:Project(marker.bearing, facing, plugin.viewAngle, width)
        if not x or alpha <= 0 then
            return false
        end
        marker.projectedX, marker.projectedAlpha, marker.projectedDelta = x, alpha, delta
    end
    return true
end

function Plugin:SelectCompassMarkers(facing, width, live)
    local selection = self.selectedMarkers
    if not facing then
        wipe(selection)
        wipe(self.selectionKeys)
        self.markerSlotsDirty = true
        self.selectionDirty = true
        return selection
    end
    if live and not self.selectionDirty and self.selectionFacing then
        local turn = CompassMath:WrapDegrees(facing - self.selectionFacing)
        -- Turning translates the same points together until one crosses the viewport edge.
        if
            (turn == 0 or (turn > self.selectionTurnMin and turn < self.selectionTurnMax))
            and ProjectSelection(self, facing, width)
        then
            return selection
        end
    end
    wipe(selection)
    self.markerSlotsDirty = true
    local halfView, turnMin, turnMax = self.viewAngle / 2, -C.HALF_TURN, C.HALF_TURN
    local profiler = Addon.Services.profiler
    local start, startKB
    if profiler and profiler.active then
        start, startKB = profiler:Begin()
    end
    for _, marker in ipairs(self.bearings) do
        if marker.bearing then
            local x, alpha, delta = CompassMath:Project(marker.bearing, facing, self.viewAngle, width)
            turnMin, turnMax = LimitTurn(delta, halfView, turnMin, turnMax)
            if x and alpha > 0 then
                if live and marker.bearingRevision ~= self.bearingRevision then
                    self:RefreshCompassMarkerBearing(marker)
                    x, alpha = nil, nil
                    if marker.bearing then
                        x, alpha, delta = CompassMath:Project(marker.bearing, facing, self.viewAngle, width)
                        turnMin, turnMax = LimitTurn(delta, halfView, turnMin, turnMax)
                    end
                end
                if x and alpha > 0 then
                    selection[#selection + 1] = marker
                    marker.projectedX, marker.projectedAlpha, marker.projectedDelta = x, alpha, delta
                    if #selection == C.MAX_MARKERS then
                        break
                    end
                end
            end
        end
    end
    wipe(self.selectionKeys)
    for _, marker in ipairs(selection) do
        self.selectionKeys[marker.key] = true
    end
    self.selectionFacing, self.selectionTurnMin, self.selectionTurnMax = facing, turnMin, turnMax
    self.selectionDirty = false
    if start then
        profiler:End(self, "Compass.Selection", start, startKB)
    end
    return selection
end
