local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local F = Addon.ClientFeatures
local Utils = Addon.SourceUtils
local Readable, Number, AddMarker = Utils.Readable, Utils.Number, Utils.AddMarker
local OFFER_ATLASES = {}
for name, atlas in pairs({
    Normal = "QuestNormal",
    Questline = "QuestNormal",
    Recurring = "UI-QuestPoiRecurring-QuestBang",
    Meta = "quest-wrapper-available",
    Calling = "Quest-DailyCampaign-Available",
    Campaign = "Quest-Campaign-Available",
    Legendary = "UI-QuestPoiLegendary-QuestBang",
    Important = "importantavailablequesticon",
}) do
    local classification = Enum.QuestClassification[name]
    if F.questOfferClasses[name] and classification ~= nil then
        OFFER_ATLASES[classification] = atlas
    end
end

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
    if not id or id <= 0 or seen[id] then
        return
    end
    local atlas = OFFER_ATLASES[Number(C_QuestInfoSystem.GetQuestClassification(id))]
    if not atlas then
        return
    end
    -- Sparse task records must not override a higher-priority quest line's visibility flags.
    seen[id] = true
    local startMapID = Number(info.startMapID)
    if not startMapID or Readable(info.inProgress) ~= false or not Utils.IsMapPosition(info) then
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
    AddMarker(plugin, markers, "offer:" .. id, info, info.questName, atlas, C.QUEST_PRIORITY, "questOffer")
end

function Plugin:CollectCompassQuestOffers(markers)
    if not F.offers or not self.showQuestOffers then
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
    local offers = Utils.ReadList(self, C_QuestLine.GetAvailableQuestLines(self.mapID))
    self:CompassDiscoveryCheckpoint()
    for _, info in ipairs(offers or {}) do
        AddOffer(self, markers, info, seen, mapCache, showHidden, showCompleted)
        self:CompassDiscoveryCheckpoint()
    end
    local forced = Utils.ReadList(self, C_QuestLine.GetForceVisibleQuests(self.mapID))
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
    if not F.tasks then
        return
    end
    local tasks = Utils.ReadList(self, C_TaskQuest.GetQuestsOnMap(self.mapID))
    self:CompassDiscoveryCheckpoint()
    for _, info in ipairs(tasks or {}) do
        info = Readable(info)
        local id = info and Number(info.questID)
        if id and id > 0 and not seen[id] and Readable(info.inProgress) == false then
            -- Task coordinates are already projected to the queried map, regardless of their source mapID.
            local offer = {
                questID = id,
                startMapID = self.mapID,
                x = info.x,
                y = info.y,
                inProgress = false,
                questName = C_TaskQuest.GetQuestInfoByQuestID(id),
                isHidden = C_QuestLog.IsQuestTrivial(id),
                isAccountCompleted = C_QuestLog.IsQuestFlaggedCompletedOnAccount(id),
            }
            AddOffer(self, markers, offer, seen, mapCache, showHidden, showCompleted)
        end
        self:CompassDiscoveryCheckpoint()
    end
end
