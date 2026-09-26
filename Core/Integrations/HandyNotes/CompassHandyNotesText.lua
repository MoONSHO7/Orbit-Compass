local _, Addon = ...
local Readable, Number = Addon.SourceUtils.Readable, Addon.SourceUtils.Number
local Text = {}
local MAX_TOKEN_PASSES = 8
local MAX_ID = 2147483647
local CRITERIA_INDEX_LIMIT = 100
local DOT_MARKUP = "|T%s:0::::16:16::16::16:%d:%d:%d|t"
local DOT_FALLBACK_COLOR = "FFFF00FF"
local COLORS = table.freeze({
    Blue = "FF0066FF",
    Bronze = "FFCD7F32",
    Gold = "FFFFD700",
    Gray = "FF999999",
    Green = "FF00FF00",
    LightBlue = "FF8080FF",
    Orange = "FFFF8C00",
    Red = "FFFF0000",
    Silver = "FFC4D4E4",
    White = "FFFFFFFF",
    Yellow = "FFFFFF00",
    Heirloom = "FF00CCFF",
    NPC = "FFFFFD00",
    Spell = "FF71D5FF",
})
local TOKEN_COLORS = table.freeze({
    achievement = "Gold",
    area = "Yellow",
    bug = "Red",
    daily = "Yellow",
    emote = "Orange",
    faction = "NPC",
    location = "Yellow",
    map = "Yellow",
    note = "Orange",
    npc = "NPC",
    object = "Yellow",
    quest = "Yellow",
    spell = "Spell",
    title = "Yellow",
    wq = "Yellow",
    yell = "Red",
})

local function ReadString(value)
    value = Readable(value)
    if type(value) == "string" and value:find("%S") then
        return value
    end
end

local function ReadTable(value)
    value = Readable(value)
    if type(value) == "table" then
        return value
    end
end

local function ReadName(value)
    value = ReadString(value)
    if value ~= ReadString(UNKNOWN) and value ~= ReadString(UNKNOWNOBJECT) and value ~= ReadString(RETRIEVING_DATA) then
        return value
    end
end

local function NamedRecord(value)
    local record = ReadTable(value)
    return record and ReadName(record.name)
end

local function ResolveName(kind, id, criteriaID)
    if kind == "npc" and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local data = ReadTable(C_TooltipInfo.GetHyperlink("unit:Creature-0-0-0-0-" .. id))
        local lines = data and ReadTable(data.lines)
        local first = lines and ReadTable(lines[1])
        local name = first and ReadName(first.leftText)
        return name, name == nil
    elseif kind == "item" and C_Item and C_Item.GetItemNameByID then
        local name = ReadName(C_Item.GetItemNameByID(id))
        if not name then
            if C_Item.DoesItemExistByID and Readable(C_Item.DoesItemExistByID(id)) == false then
                return
            end
            C_Item.RequestLoadItemDataByID(id)
        end
        return name, name == nil
    elseif kind == "spell" and C_Spell and C_Spell.GetSpellName then
        local name = ReadName(C_Spell.GetSpellName(id))
        if not name then
            C_Spell.RequestLoadSpellData(id)
        end
        return name, name == nil
    elseif kind == "quest" and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local name = ReadName(C_QuestLog.GetTitleForQuestID(id))
        if not name then
            C_QuestLog.RequestLoadQuestByID(id)
        end
        return name, name == nil
    elseif kind == "achievement" and GetAchievementInfo then
        local _, name = GetAchievementInfo(id)
        name = ReadName(name)
        return name, name == nil
    elseif kind == "criteria" and criteriaID then
        local getter
        if criteriaID < CRITERIA_INDEX_LIMIT then
            getter = GetAchievementCriteriaInfo
        else
            getter = GetAchievementCriteriaInfoByID
        end
        if getter then
            -- Providers can reference criteria that are absent from the current client's achievement data.
            local ok, name = pcall(getter, id, criteriaID, true)
            if ok then
                name = ReadName(name)
                return name, name == nil
            end
        end
    elseif kind == "map" and C_Map and C_Map.GetMapInfo then
        return NamedRecord(C_Map.GetMapInfo(id))
    elseif kind == "area" and C_Map and C_Map.GetAreaInfo then
        return ReadName(C_Map.GetAreaInfo(id))
    elseif kind == "currency" and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        return NamedRecord(C_CurrencyInfo.GetCurrencyInfo(id))
    elseif kind == "faction" and C_Reputation and C_Reputation.GetFactionDataByID then
        return NamedRecord(C_Reputation.GetFactionDataByID(id))
    end
end

local function Color(value, color)
    return "|c" .. COLORS[color] .. value .. "|r"
end

function Text:ResolveName(kind, id, misses, criteriaID)
    id = Number(id)
    if not id or id <= 0 or id > MAX_ID or id % 1 ~= 0 then
        return
    end
    if kind == "criteria" then
        criteriaID = Number(criteriaID)
        if not criteriaID or criteriaID <= 0 or criteriaID > MAX_ID or criteriaID % 1 ~= 0 then
            return
        end
    end
    local controller = Addon.Controller
    controller.handyNotesTextCache = controller.handyNotesTextCache or {}
    local cache = controller.handyNotesTextCache
    local key = kind .. ":" .. id .. (criteriaID and "." .. criteriaID or "")
    local name, pending = cache[key], misses[key]
    if not name and pending == nil then
        name, pending = ResolveName(kind, id, criteriaID)
        pending = pending == true
        if name then
            cache[key] = name
        else
            misses[key] = pending
        end
    end
    return name, pending
end

local function ResolveToken(state, kind, payload, nameOnly)
    if kind == "dot" then
        local color = COLORS[payload] or DOT_FALLBACK_COLOR
        local red, green, blue = color:match("^%x%x(%x%x)(%x%x)(%x%x)$")
        return DOT_MARKUP:format(state.dotTexture, tonumber(red, 16), tonumber(green, 16), tonumber(blue, 16))
    end
    local digits, suffix = payload:match("^(%d+)(%l*)$")
    local id = Number(tonumber(digits))
    local value = digits and (ReadString(UNKNOWN) or digits) or payload
    if id and id > 0 and id <= MAX_ID then
        local source = kind == "daily" and "quest" or kind
        local name, pending = Text:ResolveName(source, id, state.misses)
        state.incomplete = state.incomplete or pending
        value = name and name .. suffix or ReadString(pending and RETRIEVING_DATA or UNKNOWN) or digits
    end
    local color = TOKEN_COLORS[kind]
    return not nameOnly and color and Color(value, color) or value
end

local function Render(state, value, nameOnly)
    value = ReadString(value)
    if not value then
        return
    end
    for _ = 1, MAX_TOKEN_PASSES do
        local rendered, count = value:gsub("{(%l+):([^{}]+)}", function(kind, payload)
            return ResolveToken(state, kind, payload, nameOnly)
        end)
        value = rendered
        if count == 0 then
            break
        end
    end
    return value
end

function Text:Read(node, provider)
    local state = { misses = {}, incomplete = false, dotTexture = provider.dotTexture }
    local name = Render(state, node.label, true)
    local location = Render(state, node.location, false)
    local note = Render(state, node.note, false)
    local description = location
    if note and note ~= location then
        description = location and location .. "\n\n" .. note or note
    end
    return name, description, state.incomplete
end

Addon.HandyNotesText = table.freeze(Text)
