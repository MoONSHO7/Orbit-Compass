local addonName, Addon = ...
local mediaPath = "Interface\\AddOns\\" .. addonName .. "\\Assets\\"
local USE_NATIVE_LOCALE_FONT = LOCALE_koKR or LOCALE_zhCN or LOCALE_zhTW

local function resolveOrbitFontPath(fileName)
    return USE_NATIVE_LOCALE_FONT and STANDARD_TEXT_FONT or mediaPath .. "Fonts\\" .. fileName
end

local UI_PATH = resolveOrbitFontPath("OrbitSansCondensedUI-ExtraBold.ttf")
local CHAT_PATH = resolveOrbitFontPath("OrbitSansCondensedChat-Bold.ttf")

Addon.Fonts = table.freeze({
    Name = table.freeze({
        UI = "Orbit UI",
        Chat = "Orbit UI Chat",
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
})
