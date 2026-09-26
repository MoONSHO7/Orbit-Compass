local addonName, Addon = ...
local mediaPath = "Interface\\AddOns\\" .. addonName .. "\\Assets\\"

local UI_PATH = LOCALE_koKR and mediaPath .. "Fonts\\OrbitSansCondensedUIKR-ExtraBold.ttf"
    or LOCALE_zhCN and mediaPath .. "Fonts\\OrbitSansCondensedUISC-ExtraBold.ttf"
    or LOCALE_zhTW and mediaPath .. "Fonts\\OrbitSansCondensedUITC-ExtraBold.ttf"
    or mediaPath .. "Fonts\\OrbitSansCondensedUI-ExtraBold.ttf"
local CHAT_PATH = LOCALE_koKR and mediaPath .. "Fonts\\OrbitSansCondensedChatKR-Bold.ttf"
    or LOCALE_zhCN and mediaPath .. "Fonts\\OrbitSansCondensedChatSC-Bold.ttf"
    or LOCALE_zhTW and mediaPath .. "Fonts\\OrbitSansCondensedChatTC-Bold.ttf"
    or mediaPath .. "Fonts\\OrbitSansCondensedChat-Bold.ttf"

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
