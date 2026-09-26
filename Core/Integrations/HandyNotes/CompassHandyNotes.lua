local _, Addon = ...
local L = Addon.L
local C = Addon.Constants
local Plugin = Addon.Controller
local Utils = Addon.SourceUtils
local Readable, Number = Utils.Readable, Utils.Number
local HOOK_METHODS = {
    "RegisterPluginDB",
    "UpdatePluginMap",
    "UpdateWorldMap",
    "OnEnable",
    "OnDisable",
    "OnProfileChanged",
}
local COORDINATE_PERCENT = 100
local RETRY_INTERVAL = 30

local function ReadTable(value)
    value = Readable(value)
    if type(value) == "table" then
        return value
    end
end

local function ReadString(value)
    value = Readable(value)
    if type(value) == "string" and value ~= "" then
        return value
    end
end

local function ReadFunction(value)
    value = Readable(value)
    if type(value) == "function" then
        return value
    end
end

local function ReadText(value)
    value = ReadString(value)
    value = value and value:match("^%s*(.-)%s*$")
    if value ~= "" then
        return value
    end
end

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

local function ReadMapID(value)
    value = Number(value)
    if value and value > 0 and value % 1 == 0 then
        return value
    end
end

local function ReadNodeMapID(value, mapID)
    if Addon.Services.IsSecret(value, "Compass.HandyNotes") then
        return
    end
    if value == nil then
        return mapID
    end
    return ReadMapID(value)
end

local function ReadTexture(value)
    value = Readable(value)
    if type(value) == "string" and value ~= "" then
        return value
    end
    value = Number(value)
    if value and value > 0 and value % 1 == 0 then
        return value
    end
end

local function ReadNoteText(addon, mapID, coord)
    local getModule = ReadFunction(addon.GetModule)
    local module = getModule and ReadTable(getModule(addon, "HandyNotes", true))
    local database = module and ReadTable(module.db)
    local notes = database and ReadTable(database.global)
    local mapNotes = notes and ReadTable(notes[mapID])
    local note = mapNotes and ReadTable(mapNotes[coord])
    if note then
        local title, description = ReadText(note.title), ReadText(note.desc)
        if not title then
            return description
        end
        return title, description
    end
end

local function ReadMapNotesText(data, npcNames, coord)
    local note = data and ReadTable(data[coord])
    if not note then
        return
    end
    local npcID = ReadMapID(note.npcID) or ReadMapID(note.npcIDs1)
    local packed = npcID and npcNames and ReadString(npcNames[npcID])
    local npcName, npcTitle
    if packed then
        npcName, npcTitle = packed:match("^([^\031]*)\031(.*)$")
        npcName, npcTitle = ReadText(npcName), ReadText(npcTitle)
    end
    local transport, detail = ReadText(note.TransportName), ReadText(note.dnID)
    local name = ReadText(note.name) or npcName or transport or detail
    local description = npcName and npcTitle
    if description == name then
        description = nil
    end
    if transport and transport ~= name and transport ~= description then
        description = description and description .. "\n" .. transport or transport
    end
    if detail and detail ~= name and detail ~= npcTitle and detail ~= transport then
        description = description and description .. "\n" .. detail or detail
    end
    return name, description, npcID ~= nil and npcName == nil
end

local function SnapshotProvider(addon, providerName, handler, mapID, scale, alpha, iterator, state, initial)
    local snapshots = {}
    local seen = {}
    local mapNotes, npcNames, zarillionNodes, kemayoNodes
    local zarillion = Addon.HandyNotesZarillion:Get(providerName)
    local textState = { misses = {}, incomplete = false }
    if providerName == "MapNotes" then
        local context = ReadTable(state)
        if context and Number(context.uiMapId) == mapID then
            -- MapNotes returns node metadata in its pooled iterator state; copy text before the next iteration.
            mapNotes = ReadTable(context.data)
        end
        local database = ReadTable(_G.HandyNotes_MapNotesRetailNpcCacheDB)
        local names = database and ReadTable(database.names)
        npcNames = names and ReadTable(names[GetLocale()])
    elseif zarillion then
        zarillionNodes = ReadTable(state)
    elseif Addon.HandyNotesKemayo:Accepts(providerName) then
        kemayoNodes = ReadTable(state)
    end
    local incomplete = false
    for coord, nodeMapID, icon, nodeScale, nodeAlpha in iterator, state, initial do
        coord = Number(coord)
        nodeMapID = ReadNodeMapID(nodeMapID, mapID)
        if coord and coord >= 0 and coord % 1 == 0 and nodeMapID then
            local x, y = addon:getXY(coord)
            x, y = Number(x), Number(y)
            if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                icon = Readable(icon)
                local iconInfo = ReadTable(icon)
                local iconScale = Number(nodeScale) or 1
                local iconAlpha = (Number(nodeAlpha) or 1) * alpha
                if iconInfo then
                    iconAlpha = iconAlpha * (Number(iconInfo.a) or 1)
                end
                iconAlpha = math.max(0, math.min(1, iconAlpha))
                iconScale = Number(iconScale * scale)
                local key = "handynotes:" .. providerName .. ":" .. nodeMapID .. ":" .. coord
                if iconAlpha > 0 and iconScale and iconScale > 0 and not seen[key] then
                    seen[key] = true
                    local name, description, node, handynotesPoint
                    if providerName == "HandyNotes" then
                        name, description = ReadNoteText(addon, nodeMapID, coord)
                    elseif mapNotes and nodeMapID == mapID then
                        local pending
                        name, description, pending = ReadMapNotesText(mapNotes, npcNames, coord)
                        incomplete = incomplete or pending
                    elseif kemayoNodes and nodeMapID == mapID then
                        local point = ReadTable(kemayoNodes[coord])
                        if point then
                            local pending
                            name, description, pending = Addon.HandyNotesKemayo:Read(providerName, point, textState)
                            incomplete = incomplete or pending
                        end
                    elseif zarillionNodes and nodeMapID == mapID then
                        node = ReadTable(zarillionNodes[coord])
                        if node then
                            local pending
                            name, description, pending = Addon.HandyNotesText:Read(node, zarillion)
                            incomplete = incomplete or pending
                            handynotesPoint = Addon.HandyNotesClick:Capture(
                                addon,
                                providerName,
                                handler,
                                nodeMapID,
                                coord,
                                zarillionNodes,
                                node
                            )
                            if not ReadFunction(node.Render) or not ReadFunction(node.Unrender) then
                                node = nil
                            end
                        end
                    end
                    local snapshot = {
                        key = key,
                        mapID = nodeMapID,
                        x = x,
                        y = y,
                        name = name or L.PLU_COMPASS_HANDYNOTES_POINT_F:format(
                            providerName,
                            x * COORDINATE_PERCENT,
                            y * COORDINATE_PERCENT
                        ),
                        description = description,
                        handynotesNode = node,
                        handynotesPoint = handynotesPoint,
                        texture = iconInfo and ReadTexture(iconInfo.icon) or ReadTexture(icon),
                        texLeft = iconInfo and Number(iconInfo.tCoordLeft) or 0,
                        texRight = iconInfo and Number(iconInfo.tCoordRight) or 1,
                        texTop = iconInfo and Number(iconInfo.tCoordTop) or 0,
                        texBottom = iconInfo and Number(iconInfo.tCoordBottom) or 1,
                        colorR = iconInfo and Number(iconInfo.r) or 1,
                        colorG = iconInfo and Number(iconInfo.g) or 1,
                        colorB = iconInfo and Number(iconInfo.b) or 1,
                        sourceAlpha = iconAlpha,
                        sizeScale = 1,
                    }
                    snapshots[#snapshots + 1] = snapshot
                end
            end
        end
    end
    return snapshots, incomplete, textState
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
    self.compassHandyNotesHooks = self.compassHandyNotesHooks or {}
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

function Plugin:CollectCompassHandyNotes(markers)
    local job = self.discoveryJob
    if not self.compassIntegrationsEnabled or not self.showHandyNotes then
        self.compassHandyNotesGuide = nil
        return
    end
    self:ConnectCompassHandyNotes()
    local addon = self.compassHandyNotesAddon
    if not addon then
        self.compassHandyNotesGuide = nil
        return
    end
    local database = addon and ReadTable(addon.db)
    local profile = database and ReadTable(database.profile)
    local enabledPlugins = profile and ReadTable(profile.enabledPlugins)
    if not enabledPlugins then
        return RETRY_INTERVAL
    end
    if Readable(profile.enabled) ~= true or (ReadFunction(addon.IsEnabled) and Readable(addon:IsEnabled()) ~= true) then
        self.compassHandyNotesGuide = nil
        return
    end
    local scale, alpha = Number(profile.icon_scale) or 1, Number(profile.icon_alpha) or 1
    if scale <= 0 or alpha <= 0 then
        self.compassHandyNotesGuide = nil
        return
    end
    local providers = {}
    for providerName, handler in pairs(addon.plugins) do
        providerName, handler = ReadString(providerName), ReadTable(handler)
        if providerName and handler and ReadFunction(handler.GetNodes2) and Readable(enabledPlugins[providerName]) then
            providers[#providers + 1] = { name = providerName, handler = handler }
        end
    end
    table.sort(providers, function(left, right)
        return left.name < right.name
    end)
    local source = self.compassSources.handynotes
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
                profiler:Count(self, "HandyNotes/" .. reason .. "/" .. provider.name)
            end
            entry = nil
            local start, startKB, phaseStart, phaseKB, profileSource
            if profiling then
                profileSource = "Compass.HandyNotes." .. provider.name
                start, startKB = profiler:Begin()
                phaseStart, phaseKB = profiler:Begin()
            end
            -- Provider iterators share mutable state: finish and copy before discovery yields.
            local ok, iterator, state, initial = pcall(provider.handler.GetNodes2, provider.handler, self.mapID, false)
            if phaseStart then
                profiler:End(self, profileSource .. ".GetNodes2", phaseStart, phaseKB)
            end
            local records, pending, textState = iterator, nil, nil
            if ok then
                if profiling then
                    phaseStart, phaseKB = profiler:Begin()
                end
                ok, records, pending, textState = pcall(
                    SnapshotProvider,
                    addon,
                    provider.name,
                    provider.handler,
                    self.mapID,
                    scale,
                    alpha,
                    iterator,
                    state,
                    initial
                )
                if phaseStart then
                    profiler:End(self, profileSource .. ".Nodes", phaseStart, phaseKB)
                end
            end
            if start then
                profiler:End(self, profileSource, start, startKB)
            end
            if ok then
                entry = { handler = provider.handler, records = records, incomplete = pending }
                cached[provider.name] = entry
                if profiling then
                    profiler:Count(self, "HandyNotes/Records/" .. provider.name, #records)
                    if textState.textCacheHits then
                        profiler:Count(self, "HandyNotes/TextCacheHit/" .. provider.name, textState.textCacheHits)
                    end
                    if textState.textRenders then
                        profiler:Count(self, "HandyNotes/TextRendered/" .. provider.name, textState.textRenders)
                    end
                    if pending then
                        profiler:Count(self, "HandyNotes/Pending/" .. provider.name)
                    end
                end
            else
                failures[#failures + 1] = { providerName = provider.name, error = records }
                if profiling then
                    profiler:Count(self, "HandyNotes/Failed/" .. provider.name)
                end
            end
        elseif profiling then
            profiler:Count(self, "HandyNotes/CacheHit/" .. provider.name)
        end
        if entry then
            incomplete = incomplete or entry.incomplete
            for _, record in ipairs(entry.records) do
                snapshots[#snapshots + 1] = record
            end
        end
        self:CompassDiscoveryCheckpoint()
    end
    for _, failure in ipairs(failures) do
        ReportProviderError(self, failure.providerName, failure.error)
    end
    if #failures > 0 and self.discoveryJob == job then
        self:MarkCompassSourcePending()
    end
    local guidesPending = self.discoveryJob == job and self:CollectCompassHandyNotesGuides(snapshots, failures)
    incomplete = incomplete or guidesPending
    table.sort(snapshots, function(left, right)
        return left.key < right.key
    end)
    for _, snapshot in ipairs(snapshots) do
        local position = self:ProjectCompassDestination(snapshot.mapID, snapshot.x, snapshot.y)
        if position then
            local marker = Utils.AddMarker(
                self,
                markers,
                snapshot.key,
                position,
                snapshot.name,
                C.FALLBACK_ATLAS,
                C.POI_PRIORITY,
                "handynotes",
                { mapID = snapshot.mapID, x = snapshot.x, y = snapshot.y }
            )
            marker.description = snapshot.description
            marker.handynotesNode = snapshot.handynotesNode
            marker.handynotesPoint = snapshot.handynotesPoint
            marker.handynotesGuide = snapshot.handynotesGuide
            marker.texture = snapshot.texture
            marker.texLeft, marker.texRight = snapshot.texLeft, snapshot.texRight
            marker.texTop, marker.texBottom = snapshot.texTop, snapshot.texBottom
            marker.colorR, marker.colorG, marker.colorB = snapshot.colorR, snapshot.colorG, snapshot.colorB
            marker.sourceAlpha, marker.sizeScale = snapshot.sourceAlpha, snapshot.sizeScale
        end
        self:CompassDiscoveryCheckpoint()
    end
    if #failures > 0 or incomplete then
        return RETRY_INTERVAL
    end
end
