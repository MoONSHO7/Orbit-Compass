local _, Addon = ...
local L = Addon.L
local Plugin = Addon.Controller
local IsSecret = Addon.Services.IsSecret
local Readable = Addon.SourceUtils.Readable
local COORDINATE_SCALE = 100
local COORDINATE_EPSILON = 0.00001
local MAX_INPUT_LENGTH = 1024
local NUMBER_PATTERN = "([%+%-]?[%d%.]+)"

local function Number(value)
    if
        not IsSecret(value, "Compass.Waypoint")
        and type(value) == "number"
        and value == value
        and math.abs(value) < math.huge
    then
        return value
    end
end

local function Text(value)
    if not IsSecret(value, "Compass.Waypoint") and type(value) == "string" then
        return value:match("^%s*(.-)%s*$")
    end
end

function Plugin:SetWaypoint(mapID, x, y, title, description, sourceKey, handynotesPoint)
    if not Addon.ClientFeatures.supported or not self:IsActive() or self:IsProfileSuppressed() then
        return false, L.CMD_COMPASS_DISABLED
    end
    mapID, x, y = Number(mapID), Number(x), Number(y)
    if not mapID or mapID <= 0 or mapID % 1 ~= 0 or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then
        return false, L.CMD_COMPASS_INVALID
    end
    local mapInfo, canSet = C_Map.GetMapInfo(mapID), C_Map.CanSetUserWaypointOnMap(mapID)
    if
        IsSecret(mapInfo, "Compass.Waypoint")
        or not mapInfo
        or IsSecret(canSet, "Compass.Waypoint")
        or canSet ~= true
    then
        return false, L.CMD_COMPASS_UNAVAILABLE
    end
    local success = C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
    if IsSecret(success, "Compass.Waypoint") or success ~= true then
        return false, L.CMD_COMPASS_UNAVAILABLE
    end
    title, description, sourceKey = Text(title), Text(description), Text(sourceKey)
    self:RetainCompassHandyNotesGuides(sourceKey, mapID, x, y)
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    self.dismissedNavigationKey = nil
    self.waypointLabel = {
        mapID = mapID,
        x = x,
        y = y,
        title = title ~= "" and title or nil,
        description = description ~= "" and description or nil,
        sourceKey = sourceKey ~= "" and sourceKey ~= "waypoint" and sourceKey or nil,
    }
    self.waypointDirty = true
    if handynotesPoint then
        self:ActivateCompassHandyNotesPoint(handynotesPoint)
    end
    return true
end

local function TrackQuest(plugin, questID)
    if not Addon.ClientFeatures.quests then
        return false, L.CMD_COMPASS_UNAVAILABLE
    end
    if Readable(C_QuestLog.IsWorldQuest(questID)) == true then
        if not Addon.ClientFeatures.worldQuests then
            return false
        end
        C_QuestLog.AddWorldQuestWatch(questID, Enum.QuestWatchType.Manual)
    elseif Readable(C_QuestLog.IsOnQuest(questID)) == true then
        C_QuestLog.AddQuestWatch(questID)
    end
    C_SuperTrack.SetSuperTrackedQuestID(questID)
    local tracked = C_SuperTrack.GetSuperTrackedQuestID()
    if IsSecret(tracked, "Compass.Waypoint") or tracked ~= questID then
        return false
    end
    plugin.compassQuestSelection = questID
    plugin.dismissedNavigationKey = nil
    plugin.waypointDirty = true
    return true
end

function Plugin:TrackCompassLandmark(landmark)
    if
        not self:IsActive()
        or self:IsProfileSuppressed()
        or not Addon.ClientFeatures.AllowsKind(landmark.kind)
        or (landmark.questID and not Addon.SourceUtils.AllowsQuest(landmark.questID))
    then
        return false, L.CMD_COMPASS_UNAVAILABLE
    end
    if landmark.questID and TrackQuest(self, landmark.questID) then
        return true
    elseif not landmark.mapID then
        return false, L.CMD_COMPASS_UNAVAILABLE
    end
    if landmark.pinType and Addon.Constants.PIN_KEY_PREFIXES[landmark.pinType] then
        C_SuperTrack.SetSuperTrackedMapPin(landmark.pinType, landmark.id)
        local pinType, id = C_SuperTrack.GetSuperTrackedMapPin()
        if
            not IsSecret(pinType, "Compass.Waypoint")
            and not IsSecret(id, "Compass.Waypoint")
            and pinType == landmark.pinType
            and id == landmark.id
        then
            self:SelectCompassPin(landmark)
            self.dismissedNavigationKey = nil
            self.waypointDirty = true
            return true
        end
    end
    local success, reason = self:SetWaypoint(landmark.mapID, landmark.x, landmark.y, landmark.name)
    if success then
        self.waypointLabel.artwork = { atlas = landmark.atlas, kind = landmark.kind }
    end
    return success, reason
end

function Plugin:AdoptCompassUserWaypoint(mapID, x, y)
    local previousMapID, previousX, previousY = self.userWaypointMapID, self.userWaypointX, self.userWaypointY
    local observed = self.userWaypointObserved
    self.userWaypointMapID, self.userWaypointX, self.userWaypointY = mapID or false, x, y
    self.userWaypointObserved = true
    if
        observed
        and mapID
        and (mapID ~= previousMapID or x ~= previousX or y ~= previousY)
        and Readable(C_SuperTrack.IsSuperTrackingUserWaypoint()) ~= true
    then
        -- World-map placement deliberately leaves new pins untracked, and only tracked pins receive native routes.
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
end

function Plugin:ClearWaypoint()
    C_Map.ClearUserWaypoint()
    self.waypointLabel = nil
    self:ClearCompassHandyNotesGuides()
    self.waypointDirty = true
end

function Plugin:GetWaypointTitle(mapID, x, y)
    local label = self.waypointLabel
    if
        label
        and label.mapID == mapID
        and math.abs(label.x - x) < COORDINATE_EPSILON
        and math.abs(label.y - y) < COORDINATE_EPSILON
    then
        return label.title or L.PLU_COMPASS_WAYPOINT, label.description, label.sourceKey
    end
    self.waypointLabel = nil
    self:ClearCompassHandyNotesGuides()
    return L.PLU_COMPASS_WAYPOINT
end

function Plugin:SetWaypointFromText(input)
    input = Text(input)
    if not input or #input > MAX_INPUT_LENGTH then
        return false, L.CMD_COMPASS_INVALID
    end
    local command, rest = input:match("^(/%S+)%s+(.*)$")
    if command then
        command = command:lower()
        if command ~= "/way" and command ~= "/orbitway" and command ~= "/oway" then
            return false, L.CMD_COMPASS_INVALID
        end
        input = rest
    end
    local link = input:match("|H(worldmap:[^|]+)|h") or input:match("^(worldmap:[%d:%.%-]+)$")
    if link then
        local point = C_Map.GetUserWaypointFromHyperlink(link)
        if
            not IsSecret(point, "Compass.Waypoint")
            and point
            and not IsSecret(point.position, "Compass.Waypoint")
            and point.position
        then
            return self:SetWaypoint(point.uiMapID, point.position.x, point.position.y)
        end
        return false, L.CMD_COMPASS_INVALID
    end
    local mapID, coordinates = input:match("^#(%d+)%s+(.*)$")
    if mapID then
        mapID, input = tonumber(mapID), coordinates
    else
        mapID = C_Map.GetBestMapForUnit("player")
    end
    local x, y, title = input:match("^" .. NUMBER_PATTERN .. "[%s,]+" .. NUMBER_PATTERN .. "(.*)$")
    if not x or (title ~= "" and not title:match("^%s")) then
        return false, L.CMD_COMPASS_INVALID
    end
    x, y = tonumber(x), tonumber(y)
    if not x or not y then
        return false, L.CMD_COMPASS_INVALID
    end
    return self:SetWaypoint(mapID, x / COORDINATE_SCALE, y / COORDINATE_SCALE, title)
end
