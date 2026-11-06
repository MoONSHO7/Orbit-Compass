local _, Addon = ...
local L = Addon.L
local Readable, Number = Addon.SourceUtils.Readable, Addon.SourceUtils.Number
local Read = Addon.HandyNotesRead
local ReadTable, ReadString, ReadFunction = Read.Table, Read.String, Read.Callable
local COORDINATE_PERCENT = 100
local Capture = {}

local function ReadText(value)
    value = ReadString(value)
    value = value and value:match("^%s*(.-)%s*$")
    if value ~= "" then
        return value
    end
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

local function SnapshotProvider(addon, provider, mapID, scale, alpha, iterator, state, initial)
    local providerName, handler = provider.name, provider.handler
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

function Capture.Provider(plugin, addon, provider, mapID, scale, alpha, profiler)
    local start, startKB, phaseStart, phaseKB, profileSource
    if profiler then
        profileSource = "Compass.HandyNotes." .. provider.name
        start, startKB = profiler:Begin()
        phaseStart, phaseKB = profiler:Begin()
    end
    -- Provider iterators share mutable state: finish and copy before discovery yields.
    local ok, iterator, state, initial = pcall(provider.handler.GetNodes2, provider.handler, mapID, false)
    if phaseStart then
        profiler:End(plugin, profileSource .. ".GetNodes2", phaseStart, phaseKB)
    end
    local records, pending, textState = iterator, nil, nil
    if ok then
        if profiler then
            phaseStart, phaseKB = profiler:Begin()
        end
        ok, records, pending, textState =
            pcall(SnapshotProvider, addon, provider, mapID, scale, alpha, iterator, state, initial)
        if phaseStart then
            profiler:End(plugin, profileSource .. ".Nodes", phaseStart, phaseKB)
        end
    end
    if start then
        profiler:End(plugin, profileSource, start, startKB)
    end
    return ok, records, pending, textState
end

Addon.HandyNotesCapture = table.freeze(Capture)
