local _, Addon = ...
local Readable, Number = Addon.SourceUtils.Readable, Addon.SourceUtils.Number
local Text = Addon.HandyNotesText
local Kemayo = {}
local MAX_ID = 2147483647
local MAX_CACHED_TEXTS = 512
local PROVIDERS = table.freeze({
    ClassicCataclysm = true,
    BurningCrusade = true,
    WrathOfTheLichKing = true,
    MistsOfPandariaTreasures = true,
    TreasureHunter = true,
    LegionTreasures = true,
    BattleForAzerothTreasures = true,
    ShadowlandsTreasures = true,
    DragonflightTreasures = true,
    WarWithin = true,
    MidnightTreasures = true,
    WoWForever = true,
    DecorTreasureHunts = true,
    SecretFish = true,
    SecretsOfAzeroth = true,
    Stygia = true,
    LongForgottenHippogryph = true,
    HigherDimensionalLearning = true,
    EliteBattlePets = true,
    WitheredArmyTraining = true,
    SuramarLeylines = true,
    SuramarTelemancy = true,
    Kosumoth = true,
    Directions = true,
    Lorewalkers = true,
})
local TOKEN_KINDS = table.freeze({
    questname = "quest",
    worldquest = "quest",
    achievementname = "achievement",
    zone = "map",
    currencyicon = "currency",
})

local function ReadTable(value)
    value = Readable(value)
    return type(value) == "table" and value or nil
end

local function ReadText(value)
    value = Readable(value)
    if type(value) == "string" and value:find("%S") then
        if value ~= Readable(UNKNOWN) and value ~= Readable(UNKNOWNOBJECT) and value ~= Readable(RETRIEVING_DATA) then
            return value
        end
    end
end

local function ReadID(value)
    value = Number(value)
    if value and value > 0 and value <= MAX_ID and value % 1 == 0 then
        return value
    end
end

local function Resolve(state, kind, id, criteriaID)
    local name, pending = Text:ResolveName(kind, id, state.misses, criteriaID)
    state.incomplete = state.incomplete or pending == true
    return name, pending
end

local function Render(state, value, point)
    value = Readable(value)
    if type(value) == "function" then
        value = value(point)
    end
    value = ReadText(value)
    if not value then
        return
    end
    if not value:find("{", 1, true) then
        return value
    end
    local controller = Addon.Controller
    local cache = controller.handyNotesKemayoTextCache
    if not cache then
        cache = { values = {}, keys = {}, nextIndex = 1 }
        controller.handyNotesKemayoTextCache = cache
    end
    local cached = cache.values[value]
    if cached then
        state.textCacheHits = (state.textCacheHits or 0) + 1
        return cached
    end
    state.textRenders = (state.textRenders or 0) + 1
    local complete = true
    local rendered = value:gsub("{([^:}]+):([^:}]+):?([^}]*)}", function(variant, payload, fallback)
        local kind = variant:match("^([%l]+)") or variant
        kind = TOKEN_KINDS[kind] or kind
        local id, criteria = payload:match("^(%d+)%.(%d+)$")
        local name, pending
        if kind == "achievement" and id then
            name, pending = Resolve(state, "criteria", tonumber(id), tonumber(criteria))
        elseif kind == "a" and CreateAtlasMarkup then
            name = ReadText(CreateAtlasMarkup(payload == "*" and "PlayerPartyBlip" or payload))
        elseif kind == "gc" then
            name = ReadText(fallback)
        else
            name, pending = Resolve(state, kind, tonumber(payload))
        end
        complete = complete and not pending
        return name or ReadText(fallback) or variant .. ":" .. payload
    end)
    if complete then
        local index = cache.nextIndex
        local retired = cache.keys[index]
        if retired then
            cache.values[retired] = nil
        end
        cache.keys[index], cache.values[value] = value, rendered
        cache.nextIndex = index % MAX_CACHED_TEXTS + 1
    end
    return rendered
end

local function Label(state, point)
    local label = Render(state, point.label, point)
    if label then
        return label
    end
    local achievement = ReadID(point.achievement)
    local criteria = Readable(point.criteria)
    if achievement and criteria ~= nil and criteria ~= true then
        local list = ReadTable(criteria) or { criteria }
        local names = {}
        for _, criterion in ipairs(list) do
            local name = Resolve(state, "criteria", achievement, criterion)
            if not name then
                break
            end
            names[#names + 1] = name
        end
        if #names > 0 and #names == #list then
            return table.concat(names, ", ")
        end
    end
    local name = Resolve(state, "item", point.item) or Resolve(state, "npc", point.npc)
    if name then
        return name
    end
    local loot = ReadTable(point.loot)
    local first = loot and Readable(loot[1])
    local reward = ReadTable(first)
    if reward then
        local getName = Readable(reward.Name)
        if type(getName) == "function" then
            name = ReadText(getName(reward, true))
            state.incomplete = state.incomplete or name == nil
        else
            name = Resolve(state, "item", reward.id)
        end
    else
        name = Resolve(state, "item", first)
    end
    return name or Resolve(state, "achievement", achievement)
end

function Kemayo:Accepts(providerName)
    return PROVIDERS[providerName] == true
end

function Kemayo:Read(providerName, point, state)
    point = ReadTable(point)
    if not point then
        return
    end
    if providerName == "Directions" then
        return ReadText(point.name)
    elseif providerName == "Lorewalkers" then
        return Resolve(state, "criteria", point[1], point[2]), Resolve(state, "achievement", point[1]), state.incomplete
    end
    local name = Label(state, point)
    local description = Render(state, point.note, point)
    return name, description, state.incomplete
end

Addon.HandyNotesKemayo = table.freeze(Kemayo)
