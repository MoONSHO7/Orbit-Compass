local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local Utils = Addon.SourceUtils
local Readable, Number, AddMarker = Utils.Readable, Utils.Number, Utils.AddMarker
local OFFER_ATLASES = {
    [Enum.QuestClassification.Normal] = "QuestNormal",
    [Enum.QuestClassification.Questline] = "QuestNormal",
    [Enum.QuestClassification.Recurring] = "UI-QuestPoiRecurring-QuestBang",
    [Enum.QuestClassification.Meta] = "quest-wrapper-available",
    [Enum.QuestClassification.Calling] = "Quest-DailyCampaign-Available",
    [Enum.QuestClassification.Campaign] = "Quest-Campaign-Available",
    [Enum.QuestClassification.Legendary] = "UI-QuestPoiLegendary-QuestBang",
    [Enum.QuestClassification.Important] = "importantavailablequesticon",
}

local function StartsOnMap(plugin, startMapID, cache)
    if cache[startMapID] ~= nil then
        return cache[startMapID]
    end
    local mapID, visited = startMapID, {}
    while mapID and mapID > 0 and mapID ~= plugin.mapID and not visited[mapID] do
        visited[mapID] = true
        local mapInfo = Readable(C_Map.GetMapInfo(mapID))
        mapID = mapInfo and Number(mapInfo.parentMapID)
        plugin:CompassDiscoveryCheckpoint()
    end
    local matches = mapID == plugin.mapID
    cache[startMapID] = matches
    return matches
end

local function AddOffer(plugin, markers, info, seen, mapCache, showHidden, showCompleted)
    info = Readable(info)
    local id = info and Number(info.questID)
    local startMapID = info and Number(info.startMapID)
    if not id or seen[id] or not startMapID or Readable(info.inProgress) ~= false or not Utils.IsMapPosition(info) then
        return
    end
    local hidden = Readable(info.isHidden)
    if hidden == nil or (hidden and not showHidden) or not StartsOnMap(plugin, startMapID, mapCache) then
        return
    end
    local completed = Readable(info.isAccountCompleted)
    if completed == nil then
        return
    end
    if completed and not showCompleted then
        local lineID = Number(info.questLineID)
        local lineIgnores = lineID
            and Readable(C_QuestLine.QuestLineIgnoresAccountCompletedFiltering(plugin.mapID, lineID)) == true
        if not lineIgnores and Readable(C_QuestLog.QuestIgnoresAccountCompletedFiltering(id)) ~= true then
            return
        end
    end
    local atlas = OFFER_ATLASES[Number(C_QuestInfoSystem.GetQuestClassification(id))]
    if
        atlas
        and AddMarker(plugin, markers, "offer:" .. id, info, info.questName, atlas, C.QUEST_PRIORITY, "questOffer")
    then
        seen[id] = true
    end
end

function Plugin:CollectCompassQuestOffers(markers)
    if not self.showQuestOffers then
        return
    end
    if self.compassOfferMapID ~= self.mapID or self.compassOfferRequestRequired then
        self.compassOfferMapID, self.compassOfferRequestRequired = self.mapID, false
        C_QuestLine.RequestQuestLinesForMap(self.mapID)
        self:CompassDiscoveryCheckpoint()
    end
    local showHidden = Readable(C_Minimap.IsTrackingHiddenQuests()) == true
    local showCompleted = Readable(C_Minimap.IsTrackingAccountCompletedQuests()) == true
    local seen, mapCache = {}, {}
    local offers = Readable(C_QuestLine.GetAvailableQuestLines(self.mapID))
    self:CompassDiscoveryCheckpoint()
    for _, info in ipairs(offers or {}) do
        AddOffer(self, markers, info, seen, mapCache, showHidden, showCompleted)
        self:CompassDiscoveryCheckpoint()
    end
    local forced = Readable(C_QuestLine.GetForceVisibleQuests(self.mapID))
    self:CompassDiscoveryCheckpoint()
    for _, id in ipairs(forced or {}) do
        id = Number(id)
        if id and not seen[id] then
            AddOffer(
                self,
                markers,
                C_QuestLine.GetQuestLineInfo(id, self.mapID),
                seen,
                mapCache,
                showHidden,
                showCompleted
            )
        end
        self:CompassDiscoveryCheckpoint()
    end
end
