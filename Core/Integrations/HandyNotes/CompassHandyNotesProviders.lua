local _, Addon = ...
local Plugin = Addon.Controller
local Readable, Number = Addon.SourceUtils.Readable, Addon.SourceUtils.Number
local Read = Addon.HandyNotesRead
local ReadTable, ReadString, ReadFunction = Read.Table, Read.String, Read.Callable
local Capture = Addon.HandyNotesCapture
local Providers = {}

local HOOK_METHODS = {
    "RegisterPluginDB",
    "UpdatePluginMap",
    "UpdateWorldMap",
    "OnEnable",
    "OnDisable",
    "OnProfileChanged",
}

local function CoreSettingsChanged(plugin, addon)
    local database = ReadTable(addon.db)
    local profile = database and ReadTable(database.profile)
    local enabled = profile and Readable(profile.enabled) == true
    local scale = profile and Number(profile.icon_scale)
    local alpha = profile and Number(profile.icon_alpha)
    local runtimeEnabled = not ReadFunction(addon.IsEnabled) or Readable(addon:IsEnabled()) == true
    local previous = plugin.compassHandyNotesSettings
    if
        previous
        and previous.profile == profile
        and previous.enabled == enabled
        and previous.scale == scale
        and previous.alpha == alpha
        and previous.runtimeEnabled == runtimeEnabled
    then
        return false
    end
    plugin.compassHandyNotesSettings = {
        profile = profile,
        enabled = enabled,
        scale = scale,
        alpha = alpha,
        runtimeEnabled = runtimeEnabled,
    }
    return true
end

local function InvalidateProviders(plugin, providerName, reason)
    local profiler = Addon.Services.profiler
    if profiler and profiler.active then
        profiler:Count(plugin, "HandyNotes/Invalidate/" .. reason .. "/" .. (providerName or "All"))
    end
    local source = plugin.compassSources.handynotes
    local active = plugin.discoveryJob and plugin.discoveryJob.source == source
    if providerName and source.handynotesProviders then
        if active then
            local retained = {}
            for name, entry in pairs(source.handynotesProviders) do
                if name ~= providerName then
                    retained[name] = entry
                end
            end
            source.handynotesProviders = retained
        else
            source.handynotesProviders[providerName] = nil
        end
    else
        source.handynotesProviders = nil
    end
    if active then
        plugin.discoveryJob = nil
    end
    plugin:InvalidateCompassSource("ORBIT_COMPASS_HANDYNOTES")
end

local function ReportProviderError(plugin, providerName, err)
    err = ReadString(err) or type(err)
    local providerErrors = plugin.compassHandyNotesErrors[providerName]
    if not providerErrors then
        providerErrors = {}
        plugin.compassHandyNotesErrors[providerName] = providerErrors
    end
    if not providerErrors[err] then
        providerErrors[err] = true
        Addon.LibOrbitUI.Callbacks:LogError("Compass.HandyNotes", providerName, err)
    end
end

function Plugin:ConnectCompassHandyNotes()
    if not self.compassIntegrationsEnabled then
        return
    end
    local addon = ReadTable(_G.HandyNotes)
    if not addon or not ReadTable(addon.plugins) or not ReadFunction(addon.getXY) then
        self.compassHandyNotesAddon = nil
        return
    end
    local connected = self.compassHandyNotesAddon == addon
    self.compassHandyNotesAddon = addon
    local settingsChanged = CoreSettingsChanged(self, addon)
    if not connected or settingsChanged then
        InvalidateProviders(self, nil, connected and "CoreSettings" or "Connect")
    end
    self.compassHandyNotesHooks = self.compassHandyNotesHooks or setmetatable({}, { __mode = "k" })
    self.compassHandyNotesErrors = self.compassHandyNotesErrors or {}
    local hooks = self.compassHandyNotesHooks[addon]
    if not hooks then
        hooks = {}
        self.compassHandyNotesHooks[addon] = hooks
    end
    for _, method in ipairs(HOOK_METHODS) do
        if not hooks[method] and ReadFunction(addon[method]) then
            hooks[method] = true
            hooksecurefunc(
                addon,
                method,
                Addon.LibOrbitUI.Callbacks:Wrap(function(_, message, providerName)
                    if self.compassIntegrationsEnabled and self.compassHandyNotesAddon == addon then
                        if method == "UpdateWorldMap" then
                            if not CoreSettingsChanged(self, addon) then
                                return
                            end
                            providerName = nil
                        elseif method == "RegisterPluginDB" then
                            providerName = ReadString(message)
                        elseif method == "UpdatePluginMap" then
                            providerName = ReadString(providerName)
                        else
                            CoreSettingsChanged(self, addon)
                            providerName = nil
                        end
                        InvalidateProviders(self, providerName, method)
                    end
                end, "Compass.HandyNotes.Update")
            )
        end
    end
end

function Plugin:DisconnectCompassHandyNotes()
    self.compassHandyNotesAddon = nil
    self.compassHandyNotesSettings = nil
    self:InvalidateCompassSourceSettings("handynotes")
end

function Providers.Collect(plugin, addon, enabledPlugins, scale, alpha, job)
    local mapID = plugin.mapID
    local providers = {}
    for providerName, handler in pairs(addon.plugins) do
        providerName, handler = ReadString(providerName), ReadTable(handler)
        if providerName and handler and ReadFunction(handler.GetNodes2) and Readable(enabledPlugins[providerName]) then
            providers[#providers + 1] = { name = providerName, handler = handler }
        end
    end
    if plugin.discoveryJob ~= job then
        return
    end
    table.sort(providers, function(left, right)
        return left.name < right.name
    end)
    local source = plugin.compassSources.handynotes
    local cached = source.handynotesProviders or {}
    source.handynotesProviders = cached
    local snapshots = {}
    local failures = {}
    local incomplete = false
    for _, provider in ipairs(providers) do
        local entry = cached[provider.name]
        local profiler = Addon.Services.profiler
        local profiling = profiler and profiler.active
        if not entry or entry.handler ~= provider.handler or entry.incomplete then
            if profiling then
                local reason = not entry and "CacheMiss"
                    or entry.handler ~= provider.handler and "HandlerChanged"
                    or "PendingRetry"
                profiler:Count(plugin, "HandyNotes/" .. reason .. "/" .. provider.name)
            end
            entry = nil
            local ok, records, pending, textState =
                Capture.Provider(plugin, addon, provider, mapID, scale, alpha, profiling and profiler or nil)
            if plugin.discoveryJob ~= job then
                return
            end
            if ok then
                entry = { handler = provider.handler, records = records, incomplete = pending }
                cached[provider.name] = entry
                if profiling then
                    profiler:Count(plugin, "HandyNotes/Records/" .. provider.name, #records)
                    if textState.textCacheHits then
                        profiler:Count(plugin, "HandyNotes/TextCacheHit/" .. provider.name, textState.textCacheHits)
                    end
                    if textState.textRenders then
                        profiler:Count(plugin, "HandyNotes/TextRendered/" .. provider.name, textState.textRenders)
                    end
                    if pending then
                        profiler:Count(plugin, "HandyNotes/Pending/" .. provider.name)
                    end
                end
            else
                failures[#failures + 1] = { providerName = provider.name, error = records }
                if profiling then
                    profiler:Count(plugin, "HandyNotes/Failed/" .. provider.name)
                end
            end
        elseif profiling then
            profiler:Count(plugin, "HandyNotes/CacheHit/" .. provider.name)
        end
        if entry then
            incomplete = incomplete or entry.incomplete
            for _, record in ipairs(entry.records) do
                snapshots[#snapshots + 1] = record
            end
        end
        plugin:CompassDiscoveryCheckpoint()
        if plugin.discoveryJob ~= job then
            return
        end
    end
    for _, failure in ipairs(failures) do
        ReportProviderError(plugin, failure.providerName, failure.error)
    end
    return snapshots, failures, incomplete
end

Addon.HandyNotesProviders = table.freeze(Providers)
