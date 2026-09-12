local _, Addon = ...
local L = Addon.L
local C = Addon.Constants
local Plugin = Addon.Controller

local function Changed(index, key, value)
    Plugin:SetSetting(index, key, value)
    if Addon.OrbitBridge then
        Addon.App:Apply()
    end
end

local function Bind(control, index, key)
    control.key = key
    control.getValue = function()
        return Plugin:GetSetting(index, key)
    end
    control.onChange = function(value)
        Changed(index, key, value)
    end
    return control
end

local function Slider(index, key, label, minimum, maximum, step, formatter)
    local defaults = Addon.Definition.indexDefaults[index] or Addon.Definition.defaults
    return Bind({
        type = "slider",
        label = label,
        min = minimum,
        max = maximum,
        step = step,
        default = defaults[key],
        formatter = formatter,
    }, index, key)
end

local function Checkbox(index, key, label, tooltip)
    return Bind({ type = "checkbox", label = label, tooltip = tooltip, default = true }, index, key)
end

local function ComponentToggle(key, label)
    return {
        type = "checkbox",
        label = label,
        default = true,
        getValue = function()
            return not Plugin:IsComponentDisabled(key)
        end,
        onChange = function(shown)
            local values = {}
            for _, disabled in ipairs(Plugin:GetSetting(C.NAVIGATION_SYSTEM_INDEX, "DisabledComponents")) do
                if disabled ~= key then
                    values[#values + 1] = disabled
                end
            end
            if not shown then
                values[#values + 1] = key
            end
            Changed(C.NAVIGATION_SYSTEM_INDEX, "DisabledComponents", values)
        end,
    }
end

local function ArrowControls()
    return {
        Slider(
            C.NAVIGATION_SYSTEM_INDEX,
            "NavigationSize",
            L.CMN_SIZE,
            C.NAVIGATION_SIZE_MIN,
            C.NAVIGATION_SIZE_MAX,
            C.NAVIGATION_SIZE_STEP
        ),
        Slider(C.NAVIGATION_SYSTEM_INDEX, "FontSize", L.PLU_COMPASS_FONT_SIZE, C.FONT_MIN, C.FONT_MAX, 1),
        ComponentToggle("Name", L.CFG_CM_PREVIEW_NAME),
        ComponentToggle("Distance", L.PLU_COMPASS_DISTANCE),
        {
            type = "dropdown",
            label = L.PLU_COMPASS_UNITS,
            default = "yards",
            options = {
                { text = L.PLU_COMPASS_YARDS, value = "yards" },
                { text = L.PLU_COMPASS_METERS, value = "meters" },
            },
            getValue = function()
                local positions = Addon.Services.NavigationPositions(Plugin)
                local distance = positions.Distance
                return distance and distance.overrides and distance.overrides.DistanceUnits or "yards"
            end,
            onChange = function(value)
                local positions = CopyTable(Plugin:GetSetting(C.NAVIGATION_SYSTEM_INDEX, "ComponentPositions"))
                positions.Distance = positions.Distance or CopyTable(Plugin:GetDefaultComponentPositions().Distance)
                positions.Distance.overrides = positions.Distance.overrides or {}
                positions.Distance.overrides.DistanceUnits = value
                Changed(C.NAVIGATION_SYSTEM_INDEX, "ComponentPositions", positions)
            end,
        },
        Checkbox(C.SYSTEM_INDEX, "FollowTracked", L.PLU_COMPASS_FOLLOW_TRACKED),
        Checkbox(C.SYSTEM_INDEX, "ShowCorpse", L.PLU_COMPASS_CORPSE),
        Checkbox(C.SYSTEM_INDEX, "FollowTomTom", L.PLU_COMPASS_FOLLOW_TOMTOM, L.PLU_COMPASS_TOMTOM_TT),
    }
end

function Addon.SettingsTabs(index)
    if index == C.NAVIGATION_SYSTEM_INDEX then
        return { { id = "arrow", label = L.PLU_COMPASS_ARROW, controls = ArrowControls() } }
    end
    local points = {}
    for _, point in ipairs({
        { "ShowWaypoint", L.PLU_COMPASS_WAYPOINT },
        { "ShowQuestObjectives", L.PLU_COMPASS_QUEST_OBJECTIVES },
        { "ShowWorldQuests", L.PLU_COMPASS_WORLD_QUESTS },
        { "ShowFlightMasters", L.PLU_COMPASS_FLIGHT_MASTERS },
        { "ShowEvents", L.PLU_COMPASS_EVENTS },
        { "ShowRaces", L.PLU_COMPASS_RACES },
        { "ShowQuestHubs", L.PLU_COMPASS_QUEST_HUBS },
        { "ShowPOIs", L.PLU_COMPASS_ZONE_POIS },
        { "ShowVignettes", L.PLU_COMPASS_VIGNETTES },
        { "ShowDirections", L.PLU_COMPASS_DIRECTIONS },
        { "ShowMapLinks", L.PLU_COMPASS_MAP_LINKS },
        { "ShowPetTamers", L.PLU_COMPASS_PET_TAMERS },
        { "ShowDigSites", L.PLU_COMPASS_DIG_SITES },
        { "ShowTrackedContent", L.PLU_COMPASS_TRACKED_CONTENT },
        { "ShowQuestOffers", L.PLU_COMPASS_QUEST_OFFERS },
        { "ShowSavedLocations", L.PLU_COMPASS_SAVED_LOCATIONS },
    }) do
        points[#points + 1] = Checkbox(C.SYSTEM_INDEX, point[1], point[2])
    end
    return {
        {
            id = "appearance",
            label = L.PLU_COMPASS_APPEARANCE,
            controls = {
                Slider(C.SYSTEM_INDEX, "Width", L.CMN_WIDTH, C.WIDTH_MIN, C.WIDTH_MAX, C.WIDTH_STEP),
                Slider(C.SYSTEM_INDEX, "FontSize", L.PLU_COMPASS_FONT_SIZE, C.FONT_MIN, C.FONT_MAX, 1),
                Slider(C.SYSTEM_INDEX, "IconSize", L.CFG_ICON_SIZE, C.ICON_MIN, C.ICON_MAX, 1),
                Slider(
                    C.SYSTEM_INDEX,
                    "Range",
                    L.PLU_COMPASS_RANGE,
                    C.RANGE_MIN,
                    C.RANGE_MAX,
                    C.RANGE_STEP,
                    function(value)
                        return Plugin:FormatCompassDistance(value, "yards")
                    end
                ),
                Slider(
                    C.SYSTEM_INDEX,
                    "ViewAngle",
                    L.PLU_COMPASS_VIEW_ANGLE,
                    C.VIEW_MIN,
                    C.VIEW_MAX,
                    C.VIEW_STEP,
                    function(value)
                        return L.PLU_COMPASS_DEGREES_F:format(value)
                    end
                ),
            },
        },
        { id = "points", label = L.PLU_COMPASS_POINTS, controls = points },
    }
end

function Plugin:AddSettings(dialog, systemFrame)
    Addon.OrbitBridge.RenderSettings(self, dialog, systemFrame)
end
