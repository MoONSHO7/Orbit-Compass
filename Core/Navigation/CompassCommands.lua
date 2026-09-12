local _, Addon = ...
local L = Addon.L
local Plugin = Addon.Controller
local COMPAT_COMMANDS = table.freeze({
    ["/way"] = "ORBITCOMPASSWAY",
})

function Plugin:HandleWaypointCommand(input)
    input = input:match("^%s*(.-)%s*$")
    local command = input:lower()
    if command == "" or command == "help" then
        print(L.CMD_COMPASS_USAGE)
        print(L.CMD_COMPASS_LOCATIONS_USAGE)
        return
    end
    if command == "clear" or command:match("^reset%s+all$") then
        self:ClearWaypoint()
        print(L.CMD_COMPASS_CLEARED)
        return
    end
    if not self:IsActive() or self:IsProfileSuppressed() then
        print(L.CMD_COMPASS_DISABLED)
        return
    end
    local action, argument = input:match("^(%S+)%s*(.-)$")
    action = action:lower()
    if self:HandleCompassPointCommand(action, argument) or self:HandleCompassLocationCommand(action, argument) then
        return
    end
    local success, reason = self:SetWaypointFromText(input)
    print(success and L.CMD_COMPASS_SET or reason)
end

local function HandleCommand(input)
    Plugin:HandleWaypointCommand(input)
end

local function ClaimedCommands()
    local claimed = {}
    for key, handler in pairs(SlashCmdList) do
        if handler ~= HandleCommand then
            local index = 1
            local alias = _G["SLASH_" .. key .. index]
            while alias do
                claimed[alias:upper()] = true
                index = index + 1
                alias = _G["SLASH_" .. key .. index]
            end
        end
    end
    return claimed
end

local function ReleaseCommand(alias, key)
    local slashKey = "SLASH_" .. key .. "1"
    if _G[slashKey] == alias then
        _G[slashKey] = nil
    end
    if rawget(SlashCmdList, key) == HandleCommand then
        SlashCmdList[key] = nil
    end
    -- Blizzard moves imported handlers into this proxy; clearing the public table alone leaves stale registrations.
    local proxy = getmetatable(SlashCmdList).__index
    if proxy[key] == HandleCommand then
        proxy[key] = nil
    end
    local command = alias:upper()
    if hash_SlashCmdList[command] == HandleCommand then
        hash_SlashCmdList[command] = nil
    end
    if hash_ChatTypeInfoList[command] == key then
        hash_ChatTypeInfoList[command] = nil
    end
end

function Plugin:RefreshWaypointCommands()
    local claimed = ClaimedCommands()
    local added = false
    for alias, key in pairs(COMPAT_COMMANDS) do
        local command = alias:upper()
        local handler = hash_SlashCmdList[command]
        local chatType = hash_ChatTypeInfoList[command]
        if
            claimed[command]
            or (handler and handler ~= HandleCommand)
            or (chatType and chatType ~= key)
            or hash_EmoteTokenList[command]
            or IsSecureCmd(command)
        then
            ReleaseCommand(alias, key)
        elseif SlashCmdList[key] ~= HandleCommand then
            _G["SLASH_" .. key .. "1"] = alias
            SlashCmdList[key] = HandleCommand
            added = true
        end
    end
    if added then
        -- Cache our entries now so later addon registrations win the next import regardless of table iteration order.
        ChatFrameUtil.ImportAllListsToHash()
    end
end

function Plugin:QueueWaypointCommands()
    if self.waypointCommandToken then
        return
    end
    local token = {}
    local generation = self:GetLifecycleGeneration()
    self.waypointCommandToken = token
    RunNextFrame(function()
        if self.waypointCommandToken ~= token then
            return
        end
        self.waypointCommandToken = nil
        if self:IsActive() and self:GetLifecycleGeneration() == generation then
            self:RefreshWaypointCommands()
        end
    end)
end

function Plugin:EnableWaypointCommands()
    Addon.Events:On("ADDON_LOADED", self.QueueWaypointCommands, self)
    self:QueueWaypointCommands()
end

function Plugin:DisableWaypointCommands()
    self.waypointCommandToken = nil
    Addon.Events:Off("ADDON_LOADED", self.QueueWaypointCommands)
    for alias, key in pairs(COMPAT_COMMANDS) do
        ReleaseCommand(alias, key)
    end
end

if not Addon.incompatibleOrbit then
    SLASH_ORBITWAY1 = "/orbitway"
    SLASH_ORBITWAY2 = "/oway"
    SlashCmdList.ORBITWAY = HandleCommand
end
