local _, Addon = ...
local C = Addon.Constants
local Plugin = Addon.Controller
local Utils = Addon.SourceUtils
local Readable, Number, AddMarker = Utils.Readable, Utils.Number, Utils.AddMarker
local QUEST_PROGRESS_ATLAS = "Quest-In-Progress-Icon-yellow"
local QUEST_COMPLETE_ATLAS = "UI-QuestIcon-TurnIn-Normal"
local WORLD_QUEST_ATLAS = "Worldquest-icon"
local BONUS_OBJECTIVE_ATLAS = "Bonus-Objective-Star"
local THREAT_ATLAS = "worldquest-icon-nzoth"

local function AddQuest(plugin, markers, questID, position, watched, seen, taskOnly)
    if not questID or questID <= 0 or seen[questID] then
        return
    end
    local isWorld = Readable(C_QuestLog.IsWorldQuest(questID))
    local title, atlas, priority, kind
    if isWorld == true and plugin.showWorldQuests and Readable(C_TaskQuest.IsActive(questID)) == true then
        title = C_TaskQuest.GetQuestInfoByQuestID(questID)
        atlas, priority = WORLD_QUEST_ATLAS, C.WORLD_QUEST_PRIORITY
        kind = "worldQuest"
    elseif isWorld == false and plugin.showQuestObjectives then
        local classification = Number(C_QuestInfoSystem.GetQuestClassification(questID))
        if
            classification == Enum.QuestClassification.BonusObjective
            or classification == Enum.QuestClassification.Threat
        then
            if Readable(C_TaskQuest.IsActive(questID)) ~= true then
                return
            end
            if
                taskOnly
                and (
                    Number(position.mapID) ~= plugin.mapID
                    or (Readable(position.isQuestStart) == true and Readable(position.inProgress) == true)
                )
            then
                return
            end
            title = C_TaskQuest.GetQuestInfoByQuestID(questID)
            if classification == Enum.QuestClassification.BonusObjective then
                atlas = BONUS_OBJECTIVE_ATLAS
            else
                local theme = Readable(C_QuestLog.GetQuestDetailsTheme(questID))
                atlas = theme and Readable(theme.poiIcon) or THREAT_ATLAS
            end
        elseif not taskOnly and Readable(C_QuestLog.IsOnQuest(questID)) == true then
            title = C_QuestLog.GetTitleForQuestID(questID)
            atlas = Readable(C_QuestLog.IsComplete(questID)) == true and QUEST_COMPLETE_ATLAS or QUEST_PROGRESS_ATLAS
        else
            return
        end
        priority = C.QUEST_PRIORITY
        kind = "quest"
    else
        return
    end
    if watched[questID] then
        priority = C.TRACKED_QUEST_PRIORITY
    end
    if AddMarker(plugin, markers, "quest:" .. questID, position, title, atlas, priority, kind) then
        seen[questID] = true
    end
end

function Plugin:CollectCompassQuests(markers)
    if not self.showQuestObjectives and not self.showWorldQuests then
        return
    end
    local watched, seen = {}, {}
    for index = 1, Number(C_QuestLog.GetNumQuestWatches()) or 0 do
        local id = Number(C_QuestLog.GetQuestIDForQuestWatchIndex(index))
        if id then
            watched[id] = true
        end
        self:CompassDiscoveryCheckpoint()
    end
    for index = 1, Number(C_QuestLog.GetNumWorldQuestWatches()) or 0 do
        local id = Number(C_QuestLog.GetQuestIDForWorldQuestWatchIndex(index))
        if id then
            watched[id] = true
        end
        self:CompassDiscoveryCheckpoint()
    end
    local superTracked = Number(C_SuperTrack.GetSuperTrackedQuestID())
    if superTracked and superTracked > 0 then
        watched[superTracked] = true
    end
    for id in pairs(watched) do
        local x, y = C_QuestLog.GetNextWaypointForMap(id, self.mapID)
        AddQuest(self, markers, id, { x = x, y = y }, watched, seen)
        self:CompassDiscoveryCheckpoint()
    end
    if self.showQuestObjectives then
        local quests = Readable(C_QuestLog.GetQuestsOnMap(self.mapID))
        self:CompassDiscoveryCheckpoint()
        for _, info in ipairs(quests or {}) do
            info = Readable(info)
            if info and Readable(info.isQuestStart) == false and Readable(info.isMapIndicatorQuest) == false then
                AddQuest(self, markers, Number(info.questID), info, watched, seen)
            end
            self:CompassDiscoveryCheckpoint()
        end
    end
    local quests = Readable(C_TaskQuest.GetQuestsOnMap(self.mapID))
    self:CompassDiscoveryCheckpoint()
    for _, info in ipairs(quests or {}) do
        info = Readable(info)
        if info then
            AddQuest(self, markers, Number(info.questID), info, watched, seen, true)
        end
        self:CompassDiscoveryCheckpoint()
    end
end

local function CollectQuestPathFallback(plugin, markers, questID, watched, seen)
    if plugin.showQuestObjectives then
        local quests = Readable(C_QuestLog.GetQuestsOnMap(plugin.mapID))
        plugin:CompassDiscoveryCheckpoint()
        for _, info in ipairs(quests or {}) do
            info = Readable(info)
            if
                info
                and Number(info.questID) == questID
                and Readable(info.isQuestStart) == false
                and Readable(info.isMapIndicatorQuest) == false
            then
                AddQuest(plugin, markers, questID, info, watched, seen)
                if seen[questID] then
                    return
                end
            end
            plugin:CompassDiscoveryCheckpoint()
        end
    end
    local quests = Readable(C_TaskQuest.GetQuestsOnMap(plugin.mapID))
    plugin:CompassDiscoveryCheckpoint()
    for _, info in ipairs(quests or {}) do
        info = Readable(info)
        if info and Number(info.questID) == questID then
            AddQuest(plugin, markers, questID, info, watched, seen, true)
            if seen[questID] then
                return
            end
        end
        plugin:CompassDiscoveryCheckpoint()
    end
end

function Plugin:RefreshCompassQuestPath(markers)
    local tracking = Number(C_SuperTrack.GetHighestPrioritySuperTrackingType())
    local questID = tracking == Enum.SuperTrackingType.Quest and Number(C_SuperTrack.GetSuperTrackedQuestID())
    local key, replacement
    if questID and questID > 0 and (self.showQuestObjectives or self.showWorldQuests) then
        key = "quest:" .. questID
        local candidates, watched, seen = {}, { [questID] = true }, {}
        local x, y = C_QuestLog.GetNextWaypointForMap(questID, self.mapID)
        AddQuest(self, candidates, questID, { x = x, y = y }, watched, seen)
        self:CompassDiscoveryCheckpoint()
        if not seen[questID] then
            CollectQuestPathFallback(self, candidates, questID, watched, seen)
        end
        replacement = candidates[1]
    end
    local found = false
    for _, marker in ipairs(self.compassSources.quests.markers) do
        if marker.key == key then
            found = true
            if replacement then
                markers[#markers + 1] = replacement
            end
        else
            markers[#markers + 1] = marker
        end
        self:CompassDiscoveryCheckpoint()
    end
    if replacement and not found then
        markers[#markers + 1] = replacement
    end
end
