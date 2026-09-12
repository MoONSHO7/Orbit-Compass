local _, Addon = ...
local L = Addon.L
local Services = Addon.Services
local Bridge = Addon.OrbitBridge
local C = Addon.Constants

local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "ZONE_CHANGED_NEW_AREA",
    "AREA_POIS_UPDATED",
    "USER_WAYPOINT_UPDATED",
    "VIGNETTES_UPDATED",
    "VIGNETTE_MINIMAP_UPDATED",
    "QUEST_LOG_UPDATE",
    "QUEST_WATCH_LIST_CHANGED",
    "QUEST_POI_UPDATE",
    "QUEST_DATA_LOAD_RESULT",
    "SUPER_TRACKING_CHANGED",
    "WORLD_QUEST_COMPLETED_BY_SPELL",
    "TAXI_NODE_STATUS_CHANGED",
    "UI_SCALE_CHANGED",
    "DISPLAY_SIZE_CHANGED",
    "DYNAMIC_GOSSIP_POI_UPDATED",
    "SPELLS_CHANGED",
    "RESEARCH_ARTIFACT_DIG_SITE_UPDATED",
    "ARTIFACT_DIGSITE_COMPLETE",
    "CONTENT_TRACKING_UPDATE",
    "CONTENT_TRACKING_LIST_UPDATE",
    "CONTENT_TRACKING_IS_ENABLED_UPDATE",
    "TRACKABLE_INFO_UPDATE",
    "TRACKING_TARGET_INFO_UPDATE",
    "QUESTLINE_UPDATE",
    "MINIMAP_UPDATE_TRACKING",
    "QUEST_ACCEPTED",
    "QUEST_TURNED_IN",
    "PLAYER_DEAD",
    "PLAYER_ALIVE",
    "PLAYER_UNGHOST",
    "CORPSE_IN_RANGE",
    "CORPSE_OUT_OF_RANGE",
    "SUPER_TRACKING_PATH_UPDATED",
    "MODIFIER_STATE_CHANGED",
}

local Plugin = Addon.Controller
local update = Addon.LibOrbitUI.Callbacks:Wrap(function(owner, elapsed)
    owner:UpdateCompass(elapsed)
end, "Compass.OnUpdate")

-- Establish the native update owner while Compass loads, before Orbit invokes the hosted lifecycle.
Plugin.events = CreateFrame("Frame")
Plugin.compassOnUpdate = function(_, elapsed)
    local profiler = Services.profiler
    local start, startKB
    if profiler then
        start, startKB = profiler:Begin()
    end
    update(Plugin, elapsed)
    if start then
        profiler:End(Plugin, "OnUpdate", start, startKB)
    end
end

function Plugin:OnLoad()
    self.compassLocations = Bridge and Bridge.Collection(self) or Addon.Store:Collection("CompassLocations")
    local frame = CreateFrame("Frame", C.FRAME_NAME, UIParent)
    frame:Hide()
    Services.pixel:Enforce(frame, { centerAnchored = true })
    frame:SetSize(C.DEFAULT_WIDTH, C.RIBBON_HEIGHT)
    frame:SetClampedToScreen(true)
    Services.ConfigureRoot(frame, C.SYSTEM_INDEX)
    frame.systemIndex = C.SYSTEM_INDEX
    frame.disableCanvasMode = true
    frame.editModeName = self.displayName
    frame.anchorOptions = { horizontal = true, vertical = true }
    Services.pixel:Point(frame, "TOP", UIParent, "TOP", 0, C.DEFAULT_Y)
    self.frame = frame
    self.markers, self.bearings = {}, {}
    self:InitializeCompassDiscovery()
    self:CreateCompassView()
    self:CreateNavigationView()
    frame:SetScript("OnHide", function()
        self:HideCompassPeek()
        self:HideNavigationView()
    end)
    frame:SetScript("OnShow", function()
        if self.inInstance or self.hiddenByGame then
            frame:Hide()
        else
            self:RefreshCompassPeekModifier()
            self.renderDirty = true
        end
    end)
    frame:SetScript("OnSizeChanged", function()
        self:LayoutCompassArtwork()
    end)
    frame.orbitResizeBounds = {
        minW = C.WIDTH_MIN,
        maxW = C.WIDTH_MAX,
        minH = C.RIBBON_HEIGHT,
        maxH = C.RIBBON_HEIGHT,
        fallbackH = C.RIBBON_HEIGHT,
        widthKey = "Width",
        heightKey = "Height",
    }
    if Bridge then
        Bridge.AttachFrame(frame, self, C.SYSTEM_INDEX)
    end
    Services.RestorePosition(frame, C.SYSTEM_INDEX)
    self.events:SetScript("OnEvent", function(_, event, payload)
        if event == "MODIFIER_STATE_CHANGED" then
            if payload == "LALT" or payload == "RALT" then
                self:RefreshCompassPeekModifier()
            end
            return
        end
        if event == "QUESTLINE_UPDATE" and Addon.SourceUtils.Readable(payload) == true then
            self.compassOfferRequestRequired = true
        elseif event == "USER_WAYPOINT_UPDATED" then
            self.dismissedNavigationKey = nil
        elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
            self.dismissedNavigationKey = nil
        end
        if event == "PLAYER_ENTERING_WORLD" then
            self:RefreshCompassInstanceState()
        end
        if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
            self.navigationFrame.defaultPosition = nil
            if not self.inInstance then
                self:LayoutNavigationView()
            end
        elseif not self.inInstance then
            self:InvalidateCompassSource(event)
        end
    end)
end

function Plugin:RefreshCompassPeekModifier()
    local held = Addon.SourceUtils.Readable(IsAltKeyDown()) == true
    if self.peekAltHeld ~= held then
        self.peekAltHeld, self.renderDirty = held, true
        if not held then
            self:HideCompassPeek()
        end
    end
end

function Plugin:OnEnable()
    self:RefreshCompassPeekModifier()
    self.discoveryDirty = true
    self.sortElapsed = 0
    for _, event in ipairs(EVENTS) do
        self.events:RegisterEvent(event)
    end
    self.events:RegisterUnitEvent("UNIT_PHASE", "player")
    self:RegisterStandardEvents()
    self:RegisterVisibilityEvents()
    if Bridge then
        Bridge.EnableNavigationEditMode(self)
        self:WatchCanvasChanges()
        self:RegisterNavigationCanvasSettings()
        Addon.Events:On("ORBIT_LOCALE_REBUILT", function()
            self:RegisterNavigationCanvasSettings()
        end, self)
        Addon.Events:On("ORBIT_PROFILE_CHANGED", function()
            self.compassPointsToggled = false
            self:ApplyCompassPointVisibility()
            self:InvalidateCompassSourceSettings("locations")
        end, self)
    end
    self:EnableWaypointCommands()
    self:EnableCompassIntegrations()
    self.skipEditModeApply = true
    self.skipEditModeExitApply = true
    self:RefreshCompassInstanceState()
end

function Plugin:OnDisable()
    self.compassPointsToggled = false
    self.peekAltHeld = false
    self.events:SetScript("OnUpdate", nil)
    self.compassUpdating = false
    self.dismissedNavigationKey, self.nativeNavigationID = nil, nil
    self:DisableWaypointCommands()
    self:DisableCompassIntegrations()
    self.events:UnregisterAllEvents()
    self:ClearCompassMarkers()
    self:HideNavigationView()
    if Bridge then
        Bridge.DisableNavigationEditMode(self)
        Bridge.RemoveFade(self.navigationFrame)
    end
    self.navigationTarget = nil
    self:InitializeCompassDiscovery()
    wipe(self.markers)
    wipe(self.bearings)
    self.frame:Hide()
    if Bridge then
        Bridge.RemoveFade(self.frame)
        Bridge.RetireLayer(self.frame)
    end
end

function Plugin:RefreshCompassInstanceState()
    self.inInstance = IsInInstance()
    self.hiddenByGame = not Bridge and (C_PetBattles.IsInBattle() or UnitHasVehicleUI("player"))
    if self.inInstance or self.hiddenByGame then
        self.events:SetScript("OnUpdate", nil)
        self.compassUpdating = false
        self:ClearCompassMarkers()
        self:HideNavigationView()
        self.navigationTarget = nil
        self:InitializeCompassDiscovery()
        wipe(self.markers)
        wipe(self.bearings)
        self.frame:Hide()
        if Bridge then
            Bridge.RemoveFade(self.frame)
            Bridge.RemoveFade(self.navigationFrame)
            Bridge.RetireLayer(self.frame)
        end
    elseif not self.compassUpdating then
        self.discoveryDirty = true
        self.sortElapsed = 0
        if Bridge then
            Bridge.RegisterLayer(self.frame, C.SYSTEM_INDEX, self.displayName)
        end
        self.events:SetScript("OnUpdate", self.compassOnUpdate)
        self.compassUpdating = true
    end
end

function Plugin:UpdateCompass(elapsed)
    if
        self.inInstance
        or self.hiddenByGame
        or not self:IsActive()
        or self:IsProfileSuppressed()
        or not self.frame:IsVisible()
    then
        self:HideCompassPeek()
        return
    end
    self.discoveryClock = self.discoveryClock + elapsed
    self.markerClock = self.markerClock + elapsed
    self.sortElapsed = self.sortElapsed + elapsed
    local profiler = Addon.Services.profiler
    local start, startKB
    if
        self.discoveryDirty
        or self.waypointDirty
        or self.discoveryJob
        or self.discoveryPending
        or self.discoveryClock >= self.discoveryNext
        or (self.compassPointAreaRetry and self.discoveryClock >= self.compassPointAreaRetry)
    then
        if profiler and profiler.active then
            start, startKB = profiler:Begin()
        end
        self:DiscoverCompassMarkers()
        if start then
            profiler:End(self, "Compass.Discovery", start, startKB)
        end
    end
    start, startKB = nil, nil
    if profiler and profiler.active then
        start, startKB = profiler:Begin()
    end
    self:RefreshCompassBearings()
    if start then
        profiler:End(self, "Compass.Bearings", start, startKB)
    end
    local facing = self:GetCompassFacing()
    local geometryReady = self:LayoutCompassArtwork()
    if
        geometryReady
        and (
            self.renderDirty
            or self.markerRevealPending
            or self.renderFacing ~= facing
            or self.renderInteractive ~= not Addon.Services.IsEditMode()
        )
    then
        start, startKB = nil, nil
        if profiler and profiler.active then
            start, startKB = profiler:Begin()
        end
        self:RenderCompass(facing, true)
        if start then
            profiler:End(self, "Compass.Render", start, startKB)
        end
    end
end

local function CacheSourceSetting(plugin, sourceKey, field, key)
    local value = plugin:GetSetting(C.SYSTEM_INDEX, key)
    if plugin[field] ~= value then
        plugin[field] = value
        plugin:InvalidateCompassSourceSettings(sourceKey)
    end
end

function Plugin:ApplySettings()
    if not self:IsActive() or self:IsProfileSuppressed() then
        return
    end
    self:RefreshCompassInstanceState()
    self:CacheCompassPointVisibility()
    if self.inInstance or self.hiddenByGame then
        return
    end
    self.viewAngle = self:GetSetting(C.SYSTEM_INDEX, "ViewAngle")
    self.range = math.max(C.RANGE_MIN, math.min(C.RANGE_MAX, self:GetSetting(C.SYSTEM_INDEX, "Range")))
    self.iconSize = self:GetSetting(C.SYSTEM_INDEX, "IconSize")
    self.navigationSize = self:GetSetting(C.NAVIGATION_SYSTEM_INDEX, "NavigationSize")
    self:CacheNavigationComponents()
    self.showLabel = self:GetSetting(C.SYSTEM_INDEX, "ShowLabel")
    CacheSourceSetting(self, "corpse", "showCorpse", "ShowCorpse")
    self.followTracked = self:GetSetting(C.SYSTEM_INDEX, "FollowTracked")
    self.frame:SetSize(self:GetSetting(C.SYSTEM_INDEX, "Width"), C.RIBBON_HEIGHT)
    Services.RestorePosition(self.frame, C.SYSTEM_INDEX)
    self:StyleCompassView()
    self.waypointDirty = true
    self.frame:Show()
    if Bridge then
        Bridge.ApplyFade(self.frame, self)
        Bridge.ApplyFade(self.navigationFrame, self)
    end
    self:RenderNavigation(self:GetCompassFacing())
end
