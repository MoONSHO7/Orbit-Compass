local addonName, Addon = ...
local Plugin = Addon.Controller
local C = Addon.Constants
local L = Addon.L
local Utils = Addon.SourceUtils
local Readable, Number, ReadPosition = Utils.Readable, Utils.Number, Utils.ReadPosition
local OWNER = addonName
local API_VERSION = 1
local SOURCE_KEY = "navigation"
local SOURCE_EVENT = "ORBIT_COMPASS_NAVIGATION_ROUTE"
local WAYPOINT_KEY = "waypoint"
local ERROR_CONTEXT = "Compass.NavigationRoute"
local REQUIRED_METHODS =
    { "SetDestination", "ReleaseDestination", "GetGuidance", "RegisterCallback", "UnregisterCallback" }
-- Route steps read like quest objectives, with the objective tracker's own marks.
local STEP_ICON_SIZE = 12
local STEP_DONE_ICON = ("|A:ui-questtracker-tracker-check:%d:%d|a"):format(STEP_ICON_SIZE, STEP_ICON_SIZE)
local STEP_OPEN_ICON = ("|A:ui-questtracker-objective-nub:%d:%d|a"):format(STEP_ICON_SIZE, STEP_ICON_SIZE)
local STEP_DONE_COLOR, STEP_AHEAD_COLOR = "ff8c8c8c", "ffbfbfbf"
local STEP_SEPARATOR = "\n"
-- A long trip lists the current step, at most STEPS_BEHIND finished ones before it and the next ones after it.
local MAX_STEP_LINES, STEPS_BEHIND = 6, 2

local function Provider()
    local provider = Readable(_G.OrbitNavigation)
    if type(provider) ~= "table" or Number(provider.API_VERSION) ~= API_VERSION then
        return
    end
    for _, method in ipairs(REQUIRED_METHODS) do
        if type(Readable(provider[method])) ~= "function" then
            return
        end
    end
    return provider
end

-- The off-map waypoint stands in only while it is what the game tracks; a tracked quest or pin belongs to Navigation.
local function WaypointOwnsTracking()
    local tracking = Number(C_SuperTrack.GetHighestPrioritySuperTrackingType())
    return tracking == nil or tracking == Enum.SuperTrackingType.UserWaypoint
end

local function ReportError(plugin, method, err)
    err = Readable(err)
    err = type(err) == "string" and err or type(err)
    local key = method .. ":" .. err
    if not plugin.compassNavigationErrors[key] then
        plugin.compassNavigationErrors[key] = true
        Addon.LibOrbitUI.Callbacks:LogError(ERROR_CONTEXT, method, err)
    end
end

-- Provider calls cross into another addon; each distinct failure is reported once instead of on every rebuild.
local function Call(plugin, method, ...)
    local ok, first, second = pcall(plugin.compassNavigationProvider[method], ...)
    if ok then
        return first, second
    end
    ReportError(plugin, method, first)
end

local function ReadString(value)
    value = Readable(value)
    if type(value) == "string" and value ~= "" then
        return value
    end
end

-- Navigation's step list, finished steps ticked and greyed, the one being travelled white and those ahead dimmed; a
-- step's text is escaped so a name can never open markup.
local function StepLines(guidance)
    local steps, current = Readable(guidance.steps), Number(guidance.step)
    if type(steps) ~= "table" or not current or #steps == 0 then
        return nil
    end
    local count = #steps
    local first = math.max(1, math.min(current - STEPS_BEHIND, count - MAX_STEP_LINES + 1))
    local lines = {}
    for index = first, math.min(count, first + MAX_STEP_LINES - 1) do
        local text = ReadString(steps[index])
        if not text then
            return nil
        end
        text = text:gsub("|", "||")
        if index < current then
            lines[#lines + 1] = STEP_DONE_ICON .. " |c" .. STEP_DONE_COLOR .. text .. "|r"
        elseif index == current then
            lines[#lines + 1] = STEP_OPEN_ICON .. " " .. text
        else
            lines[#lines + 1] = STEP_OPEN_ICON .. " |c" .. STEP_AHEAD_COLOR .. text .. "|r"
        end
    end
    return table.concat(lines, STEP_SEPARATOR)
end

local function ReadDestination(value)
    value = Readable(value)
    if type(value) ~= "table" or not Utils.IsMapPosition(value) then
        return
    end
    local mapID = Number(value.mapID)
    if not mapID or mapID <= 0 or mapID % 1 ~= 0 then
        return
    end
    local x, y = ReadPosition(value)
    return { mapID = mapID, x = x, y = y }
end

local function SameDestination(a, b)
    if not a or not b then
        return a == b
    end
    return a.mapID == b.mapID and a.x == b.x and a.y == b.y and a.name == b.name and a.key == b.key
end

function Plugin:ConnectCompassNavigationRoute()
    if not self.compassIntegrationsEnabled or self.compassNavigationProvider then
        return
    end
    local provider = Provider()
    if not provider then
        return
    end
    self.compassNavigationProvider, self.compassNavigationPublished = provider, nil
    self.compassNavigationErrors = self.compassNavigationErrors or {}
    Call(
        self,
        "RegisterCallback",
        OWNER,
        Addon.LibOrbitUI.Callbacks:Wrap(function()
            if self.compassIntegrationsEnabled and not self.inInstance then
                self:InvalidateCompassSource(SOURCE_EVENT)
            end
        end, ERROR_CONTEXT)
    )
    self:InvalidateCompassSource(SOURCE_EVENT)
    self.waypointDirty = true
end

function Plugin:DisconnectCompassNavigationRoute()
    if not self.compassNavigationProvider then
        return
    end
    Call(self, "UnregisterCallback", OWNER)
    Call(self, "ReleaseDestination", OWNER)
    self.compassNavigationProvider, self.compassNavigationPublished = nil, nil
    self:InvalidateCompassSourceSettings(SOURCE_KEY)
end

function Plugin:CollectCompassNavigationRoute(markers)
    self:ConnectCompassNavigationRoute()
    if not self.compassNavigationProvider then
        return
    end
    local guidance = Readable(Call(self, "GetGuidance", self.mapID))
    if type(guidance) ~= "table" then
        return
    end
    local destination = ReadDestination(guidance.destination)
    local marker = Utils.AddMarker(
        self,
        markers,
        SOURCE_KEY,
        guidance,
        ReadString(guidance.name) or L.PLU_COMPASS_WAYPOINT,
        C.DIRECTIONS_ATLAS,
        C.TRACKED_QUEST_PRIORITY,
        "route",
        destination
    )
    if marker then
        marker.description = StepLines(guidance) or ReadString(guidance.text)
        marker.routeDestination = destination ~= nil
        if Readable(guidance.key) == WAYPOINT_KEY then
            marker.routeTracking = Enum.SuperTrackingType.UserWaypoint
        end
    end
end

function Plugin:GetCompassNavigationWaypointLabel(mapID, x, y)
    local provider = self.compassNavigationProvider
    if not provider or type(Readable(provider.GetWaypointLabel)) ~= "function" then
        return
    end
    local name, description = Call(self, "GetWaypointLabel", mapID, x, y)
    name = ReadString(name)
    if name then
        return name, ReadString(description)
    end
end

-- false only after a dismissal, so Navigation cannot revive the trip from native super-tracking; with nothing
-- selected Compass releases instead, letting Navigation follow native quests, pins and waypoints.
function Plugin:PublishCompassNavigationDestination(selected, allowWaypoint, dismissed)
    if not self.compassNavigationProvider then
        return
    end
    local destination
    if selected then
        destination = ReadDestination(selected.destination)
        if destination then
            destination.name, destination.key = selected.name, selected.key
        end
    elseif dismissed then
        destination = false
    elseif allowWaypoint and self.userWaypointMapID and WaypointOwnsTracking() then
        local label = self.waypointLabel
        if
            self.showWaypoint
            or (label and label.sourceKey)
            or Readable(C_SuperTrack.IsSuperTrackingUserWaypoint()) == true
        then
            local mapID, x, y = self.userWaypointMapID, self.userWaypointX, self.userWaypointY
            destination = {
                mapID = mapID,
                x = x,
                y = y,
                name = label and label.title
                    or self:GetCompassNavigationWaypointLabel(mapID, x, y)
                    or L.PLU_COMPASS_WAYPOINT,
                key = WAYPOINT_KEY,
            }
        end
    end
    if SameDestination(self.compassNavigationPublished, destination) then
        return
    end
    self.compassNavigationPublished = destination and table.freeze(destination) or destination
    if destination == nil then
        Call(self, "ReleaseDestination", OWNER)
    else
        Call(self, "SetDestination", OWNER, self.compassNavigationPublished)
    end
end
