local _, Addon = ...
local C = Addon.Constants
local CompassMath = {}
Addon.Math = CompassMath

function CompassMath:WrapDegrees(degrees)
    return (degrees + C.HALF_TURN) % C.FULL_TURN - C.HALF_TURN
end

function CompassMath:Bearing(east, north, distanceSquared)
    local distance = math.sqrt(distanceSquared)
    if distance == 0 then
        return nil, distance
    end
    -- WoW facing increases counterclockwise from north; map X grows east and map Y grows south.
    return math.deg(math.atan2(-east, north)), distance
end

function CompassMath:Project(bearing, facing, viewAngle, width)
    local delta = self:WrapDegrees(facing - bearing)
    local halfView = viewAngle / 2
    if math.abs(delta) > halfView then
        return nil, nil, delta
    end
    local fraction = delta / halfView
    local alpha = math.min(1, (1 - math.abs(fraction)) / C.EDGE_FADE_FRACTION)
    return fraction * width / 2, alpha, delta
end

table.freeze(CompassMath)
