local _, Addon = ...
local UI = Addon.LibOrbitUI
assert(UI.VERSION_MAJOR == 1 and UI.VERSION_MINOR >= 8, "Orbit Compass requires LibOrbitUI 1.8")
local family = UI.Client.family
local known = family == "retail" or family == "forever"
local retail = family == "retail"

local function Has(namespace, ...)
    if not namespace then
        return false
    end
    for index = 1, select("#", ...) do
        if type(namespace[select(index, ...)]) ~= "function" then
            return false
        end
    end
    return true
end

local features = {
    family = family,
    supported = known and Has(
        C_Map,
        "GetBestMapForUnit",
        "GetMapInfo",
        "GetMapChildrenInfo",
        "GetUserWaypoint",
        "CanSetUserWaypointOnMap",
        "SetUserWaypoint",
        "GetMapWorldSize",
        "GetPlayerMapPosition",
        "GetWorldPosFromMapPos",
        "GetMapPosFromWorldPos",
        "GetMapArtID",
        "IsCityMap",
        "GetMapRectOnMap",
        "ClearUserWaypoint",
        "GetUserWaypointFromHyperlink"
    ) and Has(
        C_SuperTrack,
        "GetHighestPrioritySuperTrackingType",
        "SetSuperTrackedUserWaypoint",
        "IsSuperTrackingUserWaypoint",
        "GetSuperTrackedMapPin",
        "SetSuperTrackedMapPin"
    ) and Has(C_EventUtils, "IsEventValid") and Has(C_Texture, "GetAtlasInfo") and Has(
        UiMapPoint,
        "CreateFromCoordinates"
    ),
    rootType = Enum.UIMapType[retail and "Cosmic" or "World"],
    worldQuests = retail
        and Has(C_TaskQuest, "IsActive", "GetQuestsOnMap", "GetQuestInfoByQuestID")
        and Has(C_QuestLog, "GetNumWorldQuestWatches", "GetQuestIDForWorldQuestWatchIndex", "AddWorldQuestWatch"),
    tasks = retail and Has(C_TaskQuest, "IsActive", "GetQuestsOnMap", "GetQuestInfoByQuestID"),
    delves = retail and Has(C_AreaPoiInfo, "GetDelvesForMap"),
    races = retail and Has(C_AreaPoiInfo, "GetDragonridingRacesForMap"),
    petTamers = retail and Has(C_PetInfo, "GetPetTamersForMap") and Has(C_Minimap, "CanTrackBattlePets"),
    digSites = retail and Has(C_ResearchInfo, "GetDigSitesForMap"),
    content = retail and Has(
        C_ContentTracking,
        "GetCollectableSourceTrackingEnabled",
        "GetCollectableSourceTypes",
        "GetTrackablesOnMap",
        "GetTitle"
    ),
    housingPins = retail,
    invasions = retail and Has(C_InvasionInfo, "GetInvasionForUiMapID", "GetInvasionInfo"),
    dungeonEntrances = Has(C_EncounterJournal, "GetDungeonEntrancesForMap"),
    journalClassification = retail and type(EJ_GetInstanceInfo) == "function",
    events = Has(C_AreaPoiInfo, "GetEventsForMap", "GetAreaPOIInfo"),
    questHubs = Has(C_AreaPoiInfo, "GetQuestHubsForMap", "GetAreaPOIInfo"),
    genericPOIs = Has(C_AreaPoiInfo, "GetAreaPOIForMap", "GetAreaPOIInfo"),
    quests = Has(
        C_QuestLog,
        "GetQuestsOnMap",
        "GetNextWaypointForMap",
        "GetNumQuestWatches",
        "GetQuestIDForQuestWatchIndex",
        "IsWorldQuest",
        "IsOnQuest",
        "IsComplete",
        "GetTitleForQuestID",
        "GetNumQuestLogEntries",
        "GetInfo",
        "AddQuestWatch"
    )
        and Has(C_QuestInfoSystem, "GetQuestClassification")
        and Has(C_SuperTrack, "GetSuperTrackedQuestID", "SetSuperTrackedQuestID"),
    offers = Has(
        C_QuestLine,
        "RequestQuestLinesForMap",
        "GetAvailableQuestLines",
        "GetForceVisibleQuests",
        "GetQuestLineInfo",
        "QuestLineIgnoresAccountCompletedFiltering"
    ) and Has(C_QuestInfoSystem, "GetQuestClassification") and Has(
        C_QuestLog,
        "QuestIgnoresAccountCompletedFiltering"
    ) and Has(C_Minimap, "IsTrackingHiddenQuests", "IsTrackingAccountCompletedQuests"),
    taxi = Has(C_TaxiMap, "GetTaxiNodesForMap"),
    directions = Has(C_GossipInfo, "GetPoiForUiMapID", "GetPoiInfo"),
    links = Has(C_Map, "GetMapLinksForMap"),
    route = Has(C_Navigation, "GetNextWaypointForMap") and Has(C_SuperTrack, "GetSuperTrackedItemName"),
    vignettes = Has(C_VignetteInfo, "GetVignettes", "GetVignetteInfo", "GetVignettePosition")
        and Has(C_SuperTrack, "GetSuperTrackedVignette"),
    corpse = Has(C_DeathInfo, "GetCorpseMapPosition"),
    graveyards = Has(C_DeathInfo, "GetGraveyardsForMap"),
}
features.content = features.content and Has(C_SuperTrack, "GetSuperTrackedContent")
features.worldQuests = features.worldQuests and features.quests
features.tasks = features.tasks and features.quests
features.supported = features.supported and type(features.rootType) == "number"
features.questOfferClasses = table.freeze({
    Normal = true,
    Questline = true,
    Important = true,
    Recurring = retail,
    Meta = retail,
    Calling = retail,
    Campaign = retail,
    Legendary = retail,
})
features.points = table.freeze({
    ShowGatherMate = known,
    ShowHandyNotes = known,
    ShowWaypoint = features.supported,
    ShowSavedLocations = features.supported,
    ShowWorldQuests = features.worldQuests,
    ShowRaces = features.races,
    ShowPetTamers = features.petTamers,
    ShowDigSites = features.digSites,
    ShowTrackedContent = features.content,
    ShowEvents = features.events,
    ShowQuestHubs = features.questHubs,
    ShowQuestObjectives = features.quests,
    ShowQuestOffers = features.offers,
    ShowFlightMasters = features.taxi,
    ShowDirections = features.directions,
    ShowMapLinks = features.links,
    ShowVignettes = features.vignettes,
    ShowPOIs = features.genericPOIs or features.dungeonEntrances or features.delves,
})
features.sources = table.freeze({
    gathermate = known,
    handynotes = known,
    locations = known,
    quests = features.quests,
    route = features.route,
    vignettes = features.vignettes,
    taxi = features.taxi,
    directions = features.directions,
    links = features.links,
    tamers = features.petTamers,
    digsites = features.digSites,
    content = features.content,
    offers = features.offers,
    corpse = features.corpse,
    map = features.genericPOIs
        or features.events
        or features.races
        or features.questHubs
        or features.delves
        or features.dungeonEntrances,
})
features.kinds = table.freeze({
    quest = features.quests,
    questOffer = features.offers,
    flightMaster = features.taxi,
    mapLink = features.links,
    cave = features.links,
    event = features.events,
    questHub = features.questHubs,
    corpse = features.corpse,
    worldQuest = features.worldQuests,
    bonusObjective = features.tasks,
    invasion = features.invasions,
    delve = features.delves,
    race = features.races,
    petTamer = features.petTamers,
    digSite = features.digSites,
    content = features.content,
    housingPlot = features.housingPins,
})

function features.AllowsKind(kind)
    return features.supported and features.kinds[kind] ~= false
end

function features.AllowsPoint(key)
    return features.supported and features.points[key] ~= false
end

Addon.ClientFeatures = table.freeze(features)
