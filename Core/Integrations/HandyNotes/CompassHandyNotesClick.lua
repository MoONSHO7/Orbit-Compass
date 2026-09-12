local _, Addon = ...
local Plugin = Addon.Controller
local UI = Addon.LibOrbitUI
local Services = Addon.Services
local Readable, Number = Addon.SourceUtils.Readable, Addon.SourceUtils.Number
local Click = {}

local function ReadTable(value)
    value = Readable(value)
    if type(value) == "table" then
        return value
    end
end

local function ReadFunction(value)
    value = Readable(value)
    if type(value) == "function" then
        return value
    end
end

function Click:Capture(addon, providerName, handler, mapID, coord, nodes, node)
    local provider = Addon.HandyNotesZarillion:Get(providerName)
    addon, handler = ReadTable(addon), ReadTable(handler)
    nodes, node = ReadTable(nodes), ReadTable(node)
    mapID, coord = Number(mapID), Number(coord)
    if
        not provider
        or not addon
        or not handler
        or not nodes
        or not node
        or not mapID
        or mapID <= 0
        or mapID % 1 ~= 0
        or not coord
        or coord < 0
        or coord % 1 ~= 0
    then
        return
    end
    providerName = provider.name
    local providers = ReadTable(addon.plugins)
    local callback = ReadFunction(handler.OnClick)
    if
        not providers
        or ReadTable(providers[providerName]) ~= handler
        or not callback
        or ReadTable(nodes[coord]) ~= node
    then
        return
    end
    return table.freeze({
        addon = addon,
        providerName = providerName,
        handler = handler,
        callback = callback,
        nodes = nodes,
        node = node,
        mapID = mapID,
        coord = coord,
    })
end

function Click:Matches(left, right)
    if left == right then
        return true
    end
    if not left or not right then
        return false
    end
    return left.addon == right.addon
        and left.providerName == right.providerName
        and left.handler == right.handler
        and left.callback == right.callback
        and left.nodes == right.nodes
        and left.node == right.node
        and left.mapID == right.mapID
        and left.coord == right.coord
end

local function IsLiveAction(action, connected)
    local addon = ReadTable(_G.HandyNotes)
    local provider = Addon.HandyNotesZarillion:Get(action.providerName)
    if not addon or addon ~= action.addon or addon ~= connected or not provider then
        return false
    end
    local providerName = provider.name
    local database = ReadTable(addon.db)
    local profile = database and ReadTable(database.profile)
    local enabled = profile and ReadTable(profile.enabledPlugins)
    if not enabled or Readable(profile.enabled) ~= true or not Readable(enabled[providerName]) then
        return false
    end
    local isEnabled = ReadFunction(addon.IsEnabled)
    if isEnabled and Readable(isEnabled(addon)) ~= true then
        return false
    end
    local providers = ReadTable(addon.plugins)
    local handler = providers and ReadTable(providers[providerName])
    if not handler or handler ~= action.handler or ReadFunction(handler.OnClick) ~= action.callback then
        return false
    end
    local providerEnabled = ReadFunction(handler.IsEnabled)
    if providerEnabled and Readable(providerEnabled(handler)) ~= true then
        return false
    end
    return ReadTable(action.nodes[action.coord]) == action.node
end

local function ReportError(plugin, stage, err)
    err = Readable(err)
    err = type(err) == "string" and err or type(err)
    local key = stage .. ":" .. err
    plugin.compassHandyNotesClickErrors = plugin.compassHandyNotesClickErrors or {}
    if not plugin.compassHandyNotesClickErrors[key] then
        plugin.compassHandyNotesClickErrors[key] = true
        UI.Callbacks:LogError("Compass.HandyNotes.Click", stage, err)
    end
end

function Plugin:ActivateCompassHandyNotesPoint(action)
    action = ReadTable(action)
    if
        not action
        or not self.compassIntegrationsEnabled
        or not self.showHandyNotes
        or not self:IsActive()
        or self:IsProfileSuppressed()
        or self.inInstance
        or Services.IsEditMode()
    then
        return false
    end
    local checked, valid = pcall(IsLiveAction, action, self.compassHandyNotesAddon)
    if not checked then
        ReportError(self, "Validate", valid)
        return false
    end
    if not valid then
        return false
    end
    local providers = self.compassSources.handynotes.handynotesProviders
    local entry = providers and providers[action.providerName]
    if not entry or entry.handler ~= action.handler then
        return false
    end
    for _, record in ipairs(entry.records) do
        if record.mapID == action.mapID and Click:Matches(record.handynotesPoint, action) then
            local label, sources = self.waypointLabel, self.compassSources
            local success, err = pcall(action.callback, self.frame, "LeftButton", true, action.mapID, action.coord)
            if not success then
                ReportError(self, "OnClick", err)
            elseif
                label
                and self.waypointLabel == label
                and self.compassSources == sources
                and self.compassIntegrationsEnabled
                and self.showHandyNotes
                and self:IsActive()
                and not self:IsProfileSuppressed()
                and not self.inInstance
                and not Services.IsEditMode()
            then
                self:SelectCompassHandyNotesGuides(action, record)
            end
            return success
        end
    end
    return false
end

Addon.HandyNotesClick = table.freeze(Click)
