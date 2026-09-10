local _, Addon = ...
local L = Addon.L
local C = Addon.Constants
local Plugin = Addon.Controller
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number

function Plugin:SetCompassTomTomTarget(target)
    self.tomtomTarget = target
    wipe(self.compassSources.tomtom.markers)
    self.waypointDirty = true
    self:InvalidateCompassSource("ORBIT_COMPASS_TOMTOM")
end

function Plugin:CaptureCompassTomTom(addon, uid, _, title)
    if not self.compassIntegrationsEnabled or not self.followTomTom or self:IsProfileSuppressed() then
        return
    end
    uid = Readable(uid)
    local target
    if type(uid) == "table" and Readable(UnitIsDeadOrGhost("player")) == false then
        local mapID, x, y = Number(uid[1]), Number(uid[2]), Number(uid[3])
        title = Readable(title) or Readable(uid.title)
        if mapID and mapID > 0 and mapID % 1 == 0 and Utils.IsMapPosition({ x = x, y = y }) then
            target = {
                addon = addon,
                uid = uid,
                mapID = mapID,
                x = x,
                y = y,
                title = type(title) == "string" and title ~= "" and title or L.PLU_COMPASS_WAYPOINT,
            }
        end
    end
    self.dismissedNavigationKey = nil
    self:SetCompassTomTomTarget(target)
end

function Plugin:ConnectCompassTomTom()
    local addon = Readable(_G.TomTom)
    if
        type(addon) ~= "table"
        or self.compassTomTomAddon == addon
        or type(addon.SetCrazyArrow) ~= "function"
        or type(addon.IsValidWaypoint) ~= "function"
        or type(addon.IsCrazyArrowEmpty) ~= "function"
        or type(addon.CrazyArrowIsHijacked) ~= "function"
    then
        return
    end
    self.compassTomTomAddon = addon
    hooksecurefunc(
        addon,
        "SetCrazyArrow",
        Addon.LibOrbitUI.Callbacks:Wrap(function(...)
            self:CaptureCompassTomTom(...)
        end, "Compass.TomTom.Selection")
    )
    if type(addon.RemoveWaypoint) == "function" then
        hooksecurefunc(
            addon,
            "RemoveWaypoint",
            Addon.LibOrbitUI.Callbacks:Wrap(function(_, uid)
                if self.compassIntegrationsEnabled and self.tomtomTarget and Readable(uid) == self.tomtomTarget.uid then
                    self:SetCompassTomTomTarget(nil)
                end
            end, "Compass.TomTom.Removal")
        )
    end
end

function Plugin:EnableCompassIntegrations()
    self.compassIntegrationsEnabled = true
    self:ConnectCompassTomTom()
    Addon.Events:On("ADDON_LOADED", self.ConnectCompassTomTom, self)
end

function Plugin:DisableCompassIntegrations()
    self.compassIntegrationsEnabled = false
    self.tomtomTarget = nil
    Addon.Events:Off("ADDON_LOADED", self.ConnectCompassTomTom)
end

function Plugin:CollectCompassTomTom(markers)
    local target = self.followTomTom and self.tomtomTarget
    if not target then
        return
    end
    local addon = target.addon
    local uid = target.uid
    if
        Number(uid[1]) ~= target.mapID
        or Number(uid[2]) ~= target.x
        or Number(uid[3]) ~= target.y
        or Addon.Services.IsSecret(uid.title, "Compass.TomTom")
    then
        self.tomtomTarget = nil
        return
    end
    if Readable(addon:IsCrazyArrowEmpty()) ~= false or Readable(addon:IsValidWaypoint(target.uid)) ~= true then
        self.tomtomTarget = nil
        return
    end
    local hijacked = addon:CrazyArrowIsHijacked()
    if
        Addon.Services.IsSecret(hijacked, "Compass.TomTom")
        or hijacked
        or Readable(UnitIsDeadOrGhost("player")) ~= false
    then
        return
    end
    local position = self:ProjectCompassDestination(target.mapID, target.x, target.y)
    if position then
        Utils.AddMarker(
            self,
            markers,
            "tomtom",
            position,
            target.title,
            C.FALLBACK_ATLAS,
            C.TRACKED_QUEST_PRIORITY,
            "tomtom",
            { mapID = target.mapID, x = target.x, y = target.y }
        )
    end
end
