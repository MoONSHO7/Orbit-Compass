local addonName, Addon = ...
local mediaPath = "Interface\\AddOns\\" .. addonName .. "\\Assets\\"
local USE_NATIVE_LOCALE_FONT = LOCALE_koKR or LOCALE_zhCN or LOCALE_zhTW
local UI_NAME, CHAT_NAME = "Orbit UI", "Orbit UI Chat"
-- Shared with Orbit and Events: Default follows the host's global font (Orbit UI alone), Blizzard is the game's own.
local DEFAULT_NAME, BLIZZARD_NAME = "Orbit Default", "Blizzard"

local function resolveOrbitFontPath(fileName)
    return USE_NATIVE_LOCALE_FONT and STANDARD_TEXT_FONT or mediaPath .. "Fonts\\" .. fileName
end

local UI_PATH = resolveOrbitFontPath("OrbitSansCondensedUI-ExtraBold.ttf")
local CHAT_PATH = resolveOrbitFontPath("OrbitSansCondensedChat-Bold.ttf")
local OWN_NAMES = { BLIZZARD_NAME, UI_NAME, CHAT_NAME }
local OWN_PATHS = { [UI_NAME] = UI_PATH, [CHAT_NAME] = CHAT_PATH, [BLIZZARD_NAME] = STANDARD_TEXT_FONT }

local function SharedMedia()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

local function NameBefore(left, right)
    local leftLower, rightLower = left:lower(), right:lower()
    return leftLower == rightLower and left < right or leftLower < rightLower
end

Addon.Fonts = table.freeze({
    Name = table.freeze({
        UI = UI_NAME,
        Chat = CHAT_NAME,
        Blizzard = BLIZZARD_NAME,
        Default = DEFAULT_NAME,
    }),
    Path = table.freeze({
        UI = UI_PATH,
        Chat = CHAT_PATH,
    }),
    License = table.freeze({
        mediaPath .. "Fonts\\licenses\\OFL-Barlow.txt",
        mediaPath .. "Fonts\\licenses\\OFL-NotoSansCJK.txt",
        mediaPath .. "Fonts\\licenses\\OFL-NotoSymbolsEmoji.txt",
    }),
    -- Default, Blizzard's face and the bundled ones first, then any font another addon shares through LibSharedMedia.
    List = function()
        local names, own, shared = { DEFAULT_NAME }, { [DEFAULT_NAME] = true }, {}
        for _, name in ipairs(OWN_NAMES) do
            names[#names + 1], own[name] = name, true
        end
        local media = SharedMedia()
        for _, name in ipairs(media and media:List("font") or {}) do
            if not own[name] then
                shared[#shared + 1] = name
            end
        end
        table.sort(shared, NameBefore)
        for _, name in ipairs(shared) do
            names[#names + 1] = name
        end
        return names
    end,
    Fetch = function(name)
        local media = SharedMedia()
        return OWN_PATHS[name] or (media and name and media:Fetch("font", name, true))
    end,
    IsOwn = function(name)
        return OWN_PATHS[name] ~= nil
    end,
})
