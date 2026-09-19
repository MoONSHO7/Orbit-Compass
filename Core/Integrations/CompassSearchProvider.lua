local _, Addon = ...
local L = Addon.L
local Plugin = Addon.Controller
local LibOrbitSearch = LibStub("LibOrbitSearch-1.0", true)
assert(LibOrbitSearch, "Orbit Compass requires LibOrbitSearch")
local PROVIDER_KEY = "compass.locations"
local PROVIDER_KIND = "locations"
local CONTINENT_KIND = "continent"
local SAVED_KEY_FORMAT = "saved:%d:%.4f:%.4f"
local FULL_TEX_COORDS = { 0, 1, 0, 1 }
local sessions = {}

local function RecordID(landmark)
    if landmark.key then
        return landmark.key
    end
    return SAVED_KEY_FORMAT:format(landmark.mapID or 0, landmark.x or 0, landmark.y or 0)
end

local Provider = {
    contract = LibOrbitSearch.PROVIDER_CONTRACT,
    kind = PROVIDER_KIND,
}

function Provider.IsAvailable()
    return Addon.ClientFeatures.supported and Plugin:IsActive() and not Plugin:IsProfileSuppressed()
end

function Provider.BeginSession(session)
    sessions[session] = { scratch = Plugin:NewCompassSearchScratch(), results = {} }
    Plugin:AcquireCompassLandmarkDemand(session, true)
    Plugin:SetCompassLandmarkListener(session, function()
        session:Invalidate()
    end)
end

function Provider.EndSession(session)
    sessions[session] = nil
    Plugin:SetCompassLandmarkListener(session, nil)
    Plugin:ReleaseCompassLandmarkDemand(session)
end

function Provider.Query(session, query)
    local state = sessions[session]
    if not state or type(query.text) ~= "string" then
        return {}
    end
    local options = { fuzzy = query.fuzzy, limit = query.limit }
    local results = Plugin:SearchCompassLandmarks(query.text, state.results, state.scratch, options)
    local records = {}
    for index, landmark in ipairs(results) do
        records[index] = {
            id = RecordID(landmark),
            tier = state.scratch.tiers[landmark],
            score = state.scratch.scores[landmark],
            landmark = landmark,
        }
    end
    if #records == 0 and Plugin:IsCompassLandmarkCatalogBuilding() then
        return records, L.PLU_COMPASS_SEARCH_INDEXING
    end
    return records
end

function Provider.Present(record)
    local landmark = record.landmark
    local presentation = { name = landmark.name, detail = landmark.zone or landmark.continent }
    if landmark.texture then
        presentation.texture = landmark.texture
        presentation.texCoords = {
            landmark.texLeft or FULL_TEX_COORDS[1],
            landmark.texRight or FULL_TEX_COORDS[2],
            landmark.texTop or FULL_TEX_COORDS[3],
            landmark.texBottom or FULL_TEX_COORDS[4],
        }
        presentation.vertexColor = { r = landmark.colorR or 1, g = landmark.colorG or 1, b = landmark.colorB or 1 }
    elseif Addon.Artwork.Exists(landmark.atlas) then
        presentation.atlas = landmark.atlas
    else
        presentation.texture = Addon.Artwork.fallbackTexture
    end
    return presentation
end

function Provider.Activate(record)
    local landmark = record.landmark
    if landmark.kind == CONTINENT_KIND then
        return { close = false, replaceText = landmark.name .. " " }
    end
    local success, reason = Plugin:ChooseCompassSearchResult(landmark)
    if not success then
        return { close = true, message = reason }
    end
    return { close = true }
end

local function MarkRenderDirty()
    Plugin.compassSearchHosted = Plugin.compassSearchProviderConnected == true
        and LibOrbitSearch:IsKindIncluded(PROVIDER_KIND)
    Plugin.renderDirty = true
end

function Plugin:ConnectCompassSearchProvider()
    if self.compassSearchProviderConnected then
        return
    end
    self.compassSearchProviderConnected = LibOrbitSearch:RegisterProvider(PROVIDER_KEY, Provider) == true
    LibOrbitSearch.RegisterCallback(Provider, "InclusionChanged", MarkRenderDirty)
    MarkRenderDirty()
end

function Plugin:DisconnectCompassSearchProvider()
    if not self.compassSearchProviderConnected then
        return
    end
    LibOrbitSearch.UnregisterCallback(Provider, "InclusionChanged")
    LibOrbitSearch:UnregisterProvider(PROVIDER_KEY)
    self.compassSearchProviderConnected = false
    MarkRenderDirty()
end

function Plugin:IsCompassSearchHosted()
    return self.compassSearchHosted == true
end
