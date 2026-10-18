local _, Addon = ...
local L = Addon.L
local C = Addon.Constants
local F = Addon.ClientFeatures
local Plugin = Addon.Controller
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local NAVIGATION_RANK = { corpse = 1, provider = 2, route = 3, selected = 4, directions = 5 }
local ROUTE_DISMISSAL = "route"
local PROVIDER_SOURCE = "navigation"

function Plugin:CollectCompassCorpse(markers)
    if F.corpse and self.showCorpse and Readable(UnitIsGhost("player")) == true then
        local position = Readable(C_DeathInfo.GetCorpseMapPosition(self.mapID))
        if Utils.IsMapPosition(position) then
            Utils.AddMarker(
                self,
                markers,
                "corpse",
                position,
                L.PLU_COMPASS_CORPSE,
                C.FALLBACK_ATLAS,
                C.TRACKED_QUEST_PRIORITY,
                "corpse"
            )
        end
    end
end

local function NativeSelection()
    local tracking = C_SuperTrack.GetHighestPrioritySuperTrackingType()
    if Addon.Services.IsSecret(tracking, "Compass.SuperTracking") then
        return {}
    end
    tracking = Number(tracking)
    if F.quests and tracking == Enum.SuperTrackingType.Quest then
        local id = Number(C_SuperTrack.GetSuperTrackedQuestID())
        return id and { "quest:" .. id } or {}
    elseif F.content and tracking == Enum.SuperTrackingType.Content then
        local contentType, id = C_SuperTrack.GetSuperTrackedContent()
        contentType, id = Number(contentType), Number(id)
        return contentType and id and { "content:" .. contentType .. ":" .. id .. ":" } or {}, true
    elseif tracking == Enum.SuperTrackingType.MapPin then
        local pinType, id = C_SuperTrack.GetSuperTrackedMapPin()
        pinType, id = Number(pinType), Number(id)
        local prefixes = pinType and C.PIN_KEY_PREFIXES[pinType]
        if prefixes and id then
            local keys = {}
            for _, prefix in ipairs(prefixes) do
                keys[#keys + 1] = prefix .. id
            end
            return keys
        end
        return {}
    elseif F.vignettes and tracking == Enum.SuperTrackingType.Vignette then
        local guid = Readable(C_SuperTrack.GetSuperTrackedVignette())
        if type(guid) == "string" then
            return { "vignette:" .. guid }
        end
        return {}
    elseif tracking and tracking ~= Enum.SuperTrackingType.UserWaypoint then
        return {}
    end
end

local function MatchesSelection(markerKey, keys, prefix)
    for _, key in ipairs(keys) do
        if markerKey == key or (prefix and markerKey:sub(1, #key) == key) then
            return true
        end
    end
    return false
end

function Plugin:SelectCompassNavigation()
    -- Dismissals reset on native changes even without Follow Targets, so a new super-track reaches Orbit Navigation.
    local keys, prefix = NativeSelection()
    local selectionID = keys and (keys[1] or "unavailable")
    if self.nativeNavigationID ~= selectionID then
        self.nativeNavigationID = selectionID
        self.dismissedNavigationKey = nil
    end
    if not self:FollowsCompassPin(self:GetCompassTrackedPin()) then
        keys, prefix = nil, nil
    end
    local x, y, positionRead
    local target, bestRank, bestDistance, selected, selectedDistance
    for _, marker in ipairs(self.markers) do
        marker.navigation = false
        local rank
        if marker.kind == "corpse" then
            rank = NAVIGATION_RANK.corpse
        elseif marker.kind == "route" then
            rank = marker.source == PROVIDER_SOURCE and NAVIGATION_RANK.provider or NAVIGATION_RANK.route
        elseif marker.key == "waypoint" and not keys then
            rank = NAVIGATION_RANK.selected
        elseif keys and MatchesSelection(marker.key, keys, prefix) then
            rank = NAVIGATION_RANK.selected
        end
        if not rank and not keys and self.followTracked and marker.kind == "directions" then
            rank = NAVIGATION_RANK.directions
        end
        local dismissed = marker.key == self.dismissedNavigationKey
            or (self.dismissedNavigationKey == ROUTE_DISMISSAL and rank ~= NAVIGATION_RANK.corpse)
        if rank and not dismissed then
            if not positionRead then
                x, y = Utils.ReadPosition(C_Map.GetPlayerMapPosition(self.mapID, "player"))
                positionRead = true
            end
            local distance = x and y and ((marker.x - x) * self.mapWidth) ^ 2 + ((marker.y - y) * self.mapHeight) ^ 2
                or 0
            if rank == NAVIGATION_RANK.selected and (not selected or distance < selectedDistance) then
                selected, selectedDistance = marker, distance
            end
            if
                not target
                or rank < bestRank
                or (
                    rank == bestRank
                    and (distance < bestDistance or (distance == bestDistance and marker.key < target.key))
                )
            then
                target, bestRank, bestDistance = marker, rank, distance
            end
        end
    end
    local dismissedKey = self.dismissedNavigationKey
    local dismissed = dismissedKey == ROUTE_DISMISSAL
        or (keys ~= nil and dismissedKey ~= nil and MatchesSelection(dismissedKey, keys, prefix))
    self:PublishCompassNavigationDestination(selected, not keys, dismissed)
    if target and target.kind == "route" and selected then
        local east, north = (selected.x - target.x) * self.mapWidth, (selected.y - target.y) * self.mapHeight
        local useSelected = target.source ~= PROVIDER_SOURCE
            or (x and y and selectedDistance <= C.ARRIVAL_DISTANCE * C.ARRIVAL_DISTANCE)
        -- Orbit's final walk keeps its step list until the player also reaches the destination.
        if useSelected and east * east + north * north <= C.ARRIVAL_DISTANCE * C.ARRIVAL_DISTANCE then
            target = selected
        end
    end
    self.navigationKey = target and target.key
    if target then
        target.navigation = true
    end
    local profiler = Addon.Services.profiler
    if profiler and profiler.active then
        profiler:Count(self, positionRead and "Navigation/PositionRead" or "Navigation/NoCandidates")
    end
end

function Plugin:DismissCompassNavigation()
    local target = self.navigationTarget
    if target and (target.key == "waypoint" or target.routeTracking == Enum.SuperTrackingType.UserWaypoint) then
        self:ClearWaypoint()
    elseif target and target.kind == "route" then
        self.dismissedNavigationKey = ROUTE_DISMISSAL
        self.waypointDirty = true
    elseif target then
        self.dismissedNavigationKey = target.key
        self.waypointDirty = true
    end
    self.navigationTarget = nil
    self:HideNavigationView()
end
