local _, Addon = ...
local Plugin = Addon.Controller
local Services = Addon.Services
local UI = Addon.LibOrbitUI
local Readable = Addon.SourceUtils.Readable
local GameTooltip = Services.tooltip

local function ReportError(plugin, stage, err)
    err = Readable(err)
    err = type(err) == "string" and err or type(err)
    local key = stage .. ":" .. err
    plugin.compassHandyNotesTooltipErrors = plugin.compassHandyNotesTooltipErrors or {}
    if not plugin.compassHandyNotesTooltipErrors[key] then
        plugin.compassHandyNotesTooltipErrors[key] = true
        UI.Callbacks:LogError("Compass.HandyNotes.Tooltip", stage, err)
    end
end

local function IsCurrentHover(plugin, button, marker)
    return plugin.hoveredCompassMarker == button
        and button.marker == marker
        and button.interactive == true
        and button.renderShown == true
        and not Services.IsEditMode()
end

local function ReadMethods(node)
    return Readable(node.Prepare), Readable(node.Render), Readable(node.Unrender)
end

local function Unrender(plugin, record)
    if record.inProviderCall or record.unrendered then
        return
    end
    record.unrendered = true
    local success, err = pcall(record.unrender, record.node, GameTooltip)
    if not success then
        ReportError(plugin, "Unrender", err)
    end
end

function Plugin:HideCompassHandyNotesTooltip(button)
    local record = button.handynotesTooltip
    if not record then
        return
    end
    button.handynotesTooltip = nil
    if GameTooltip:IsOwned(button) then
        Services.tooltipHide()
    end
    Unrender(self, record)
end

local function FailTooltip(plugin, button, record, stage, err)
    button.handynotesTooltipFailed = record.marker
    plugin:HideCompassHandyNotesTooltip(button)
    ReportError(plugin, stage, err)
end

function Plugin:ShowCompassHandyNotesTooltip(button, marker, fallback)
    if not IsCurrentHover(self, button, marker) or button.handynotesTooltipFailed == marker then
        return false
    end
    local node = Readable(marker.handynotesNode)
    if type(node) ~= "table" then
        return false
    end
    local previous = button.handynotesTooltip
    if previous and previous.marker == marker and previous.node == node then
        return true
    end
    self:HideCompassHandyNotesTooltip(button)
    local success, prepare, render, unrender = pcall(ReadMethods, node)
    if not success then
        button.handynotesTooltipFailed = marker
        ReportError(self, "Methods", prepare)
        return false
    end
    if type(prepare) ~= "function" or type(render) ~= "function" or type(unrender) ~= "function" then
        button.handynotesTooltipFailed = marker
        return false
    end
    local record = { marker = marker, node = node, unrender = unrender, inProviderCall = true }
    button.handynotesTooltip = record
    local prepared, err = pcall(prepare, node)
    record.inProviderCall = false
    if button.handynotesTooltip ~= record then
        Unrender(self, record)
        if not prepared then
            ReportError(self, "Prepare", err)
        end
        return true
    end
    if not prepared then
        FailTooltip(self, button, record, "Prepare", err)
        return false
    end
    C_Timer.After(
        0,
        UI.Callbacks:Wrap(function()
            if button.handynotesTooltip ~= record then
                return
            end
            if not IsCurrentHover(self, button, marker) then
                self:HideCompassHandyNotesTooltip(button)
                return
            end
            Services.AnchorTooltip(GameTooltip, button)
            record.inProviderCall = true
            local rendered, renderError = pcall(render, node, GameTooltip, false)
            record.inProviderCall = false
            if button.handynotesTooltip ~= record then
                Unrender(self, record)
                if not rendered then
                    ReportError(self, "Render", renderError)
                end
                return
            end
            if not rendered then
                FailTooltip(self, button, record, "Render", renderError)
                if IsCurrentHover(self, button, marker) then
                    fallback(button)
                end
                return
            end
            if not IsCurrentHover(self, button, marker) then
                self:HideCompassHandyNotesTooltip(button)
                return
            end
            GameTooltip:Show()
        end, "Compass.HandyNotes.Tooltip")
    )
    return true
end
