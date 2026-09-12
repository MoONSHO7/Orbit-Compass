local _, Addon = ...
local Readable = Addon.SourceUtils.Readable
local Zarillion = {}
local PROVIDER_NAMES = table.freeze({
    "HandyNotes_WorldOfWarcraft",
    "HandyNotes_TheBurningCrusade",
    "HandyNotes_WrathOfTheLichKing",
    "HandyNotes_Cataclysm",
    "HandyNotes_MistsOfPandaria",
    "HandyNotes_WarlordsOfDraenor",
    "HandyNotes_Legion",
    "HandyNotes_BattleForAzeroth",
    "HandyNotes_Shadowlands",
    "HandyNotes_Dragonflight",
    "HandyNotes_TheWarWithin",
    "HandyNotes_Midnight",
})
local PROVIDERS = {}
for _, name in ipairs(PROVIDER_NAMES) do
    PROVIDERS[name] = table.freeze({
        name = name,
        dotTexture = "Interface\\Addons\\" .. name .. "\\core\\artwork\\glows\\peg.blp",
        circleTexture = "Interface\\AddOns\\" .. name .. "\\core\\artwork\\circle",
    })
end
table.freeze(PROVIDERS)

function Zarillion:Get(providerName)
    providerName = Readable(providerName)
    if type(providerName) == "string" then
        return PROVIDERS[providerName]
    end
end

Addon.HandyNotesZarillion = table.freeze(Zarillion)
