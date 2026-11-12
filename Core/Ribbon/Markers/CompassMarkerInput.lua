local _, Addon = ...
local L = Addon.L
local Services = Addon.Services
local Plugin = Addon.Controller
local GameTooltip = Services.tooltip
local TYPE_COLOR = { r = 1, g = 0.82, b = 0 }
local FAILURE_COLOR = { r = 1, g = 0.2, b = 0.2 }
local GATHERMATE_KIND_PREFIX = "gathermate:"
local TYPE_LABELS = Addon.Constants.POINT_TYPE_LABELS
local NO_LINES = {}

local Input = {}
Addon.CompassMarkerInput = Input

local function LeaveMarker(button)
    Plugin:HideCompassHandyNotesTooltip(button)
    if Plugin.hoveredCompassMarker == button then
        Plugin.hoveredCompassMarker = nil
    end
    if GameTooltip:IsOwned(button) then
        Services.tooltipHide()
    end
    button.pressedMarker, button.tooltipDistance, button.failureReason = nil, nil, nil
    button.tooltipMarker, button.tooltipGroupCount = nil, nil
    button.handynotesTooltipFailed = nil
end

local function ShowMarkerTooltip(button)
    local marker = button.marker
    if not marker or Addon.Services.IsEditMode() then
        return
    end
    button.tooltipMarker = marker
    button.tooltipDistance = Plugin:CompassDisplayDistance(marker.distance)
    button.tooltipUnits = Plugin.distanceUnits
    button.tooltipGroupCount = #marker.overlapGroup.actions
    Plugin.hoveredCompassMarker = button
    if
        not button.failureReason
        and button.handynotesTooltipFailed ~= marker
        and Plugin:ShowCompassHandyNotesTooltip(button, marker, ShowMarkerTooltip)
    then
        return
    end
    Plugin:HideCompassHandyNotesTooltip(button)
    if GameTooltip:IsShown() and GameTooltip:IsOwned(button) then
        GameTooltip:ClearLines()
    else
        Services.AnchorTooltip(GameTooltip, button)
    end
    GameTooltip:SetText(marker.name, 1, 1, 1)
    GameTooltip:AddLine(Plugin:FormatCompassDistance(marker.distance), 1, 1, 1)
    local typeLabel = marker.kind:sub(1, #GATHERMATE_KIND_PREFIX) == GATHERMATE_KIND_PREFIX and L.PLU_COMPASS_GATHERMATE
        or L[TYPE_LABELS[marker.kind]]
    GameTooltip:AddLine(typeLabel, TYPE_COLOR.r, TYPE_COLOR.g, TYPE_COLOR.b)
    for _, line in ipairs(marker.tooltipLines or NO_LINES) do
        GameTooltip:AddLine(line.text, line.r, line.g, line.b)
    end
    if button.tooltipGroupCount > 1 and not marker.displayOnly then
        GameTooltip:AddLine(L.PLU_COMPASS_OVERLAP_HINT_F:format(button.tooltipGroupCount), 1, 1, 1, true)
    end
    if button.failureReason then
        GameTooltip:AddLine(button.failureReason, FAILURE_COLOR.r, FAILURE_COLOR.g, FAILURE_COLOR.b, true)
    end
    GameTooltip:Show()
end

local function SameDestination(a, b)
    return a.key == b.key
        and a.destination.mapID == b.destination.mapID
        and a.destination.x == b.destination.x
        and a.destination.y == b.destination.y
        and Addon.HandyNotesClick:Matches(a.handynotesPoint, b.handynotesPoint)
end

local function ClickMarker(button)
    local pressed, marker = button.pressedMarker, button.marker
    button.pressedMarker = nil
    if
        not pressed
        or not marker
        or marker.displayOnly
        or Addon.Services.IsEditMode()
        or not SameDestination(pressed, marker)
    then
        return
    end
    local actions = marker.overlapGroup.actions
    if #actions > 1 then
        LeaveMarker(button)
        Plugin:ShowCompassOverlapMenu(actions)
        return
    end
    if marker.kind == "route" then
        return
    end
    local destination = marker.destination
    local success, reason = Plugin:SetWaypoint(
        destination.mapID,
        destination.x,
        destination.y,
        marker.name,
        marker.description,
        marker.sourceKey or marker.key,
        marker.handynotesPoint
    )
    if not success then
        button.failureReason = reason
        ShowMarkerTooltip(button)
    end
end

Input.Leave = LeaveMarker

function Input.Install(button)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnEnter", ShowMarkerTooltip)
    button:SetScript("OnLeave", LeaveMarker)
    button:SetScript("OnHide", LeaveMarker)
    button:SetScript("OnMouseDown", function(frame, mouseButton)
        if mouseButton == "LeftButton" and not Addon.Services.IsEditMode() then
            frame.pressedMarker = frame.marker
        end
    end)
    button:SetScript("OnClick", ClickMarker)
end

function Input.Bind(self, button, marker, interactive)
    local changed = button.marker ~= marker
    if changed then
        self:HideCompassHandyNotesTooltip(button)
        button.handynotesTooltipFailed = nil
    end
    if changed and button.marker then
        button.marker.renderShown = false
    end
    button.marker = marker
    if changed then
        button.failureReason = nil
    end
    if button.interactive ~= interactive then
        button.interactive = interactive
        button:EnableMouse(interactive)
        if not interactive then
            LeaveMarker(button)
        end
    end
    if changed and interactive and self.hoveredCompassMarker == button then
        ShowMarkerTooltip(button)
    end
end

function Plugin:RefreshCompassTooltip()
    local button = self.hoveredCompassMarker
    if button and button.handynotesTooltip then
        if button.tooltipMarker ~= button.marker then
            self:HideCompassHandyNotesTooltip(button)
            ShowMarkerTooltip(button)
        end
        return
    end
    if button and GameTooltip:IsShown() and GameTooltip:IsOwned(button) then
        local marker = button.marker
        if
            button.tooltipMarker ~= marker
            or button.tooltipDistance ~= self:CompassDisplayDistance(marker.distance)
            or button.tooltipUnits ~= self.distanceUnits
            or button.tooltipGroupCount ~= #marker.overlapGroup.actions
        then
            ShowMarkerTooltip(button)
        end
    end
end

table.freeze(Input)
