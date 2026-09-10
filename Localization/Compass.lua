local _, Addon = ...

local STRINGS = {
    enUS = {
        PLU_COMPASS_ARROW = "Arrow",
        PLU_COMPASS_ARROW_TITLE = "Compass: Arrow",
        MSG_COMPASS_NOT_READY = "Compass settings are unavailable.",
        MSG_COMPASS_INCOMPATIBLE_ORBIT = "Orbit: Compass could not start. Update Orbit, or disable Orbit and reload to use standalone Compass.",
        CMD_COMPASS_DISABLED = "Enable Compass in its settings to use the navigation arrow.",
    },
    deDE = {
        PLU_COMPASS_ARROW = "Pfeil",
        PLU_COMPASS_ARROW_TITLE = "Kompass: Pfeil",
        MSG_COMPASS_NOT_READY = "Kompass-Einstellungen sind nicht verfügbar.",
        MSG_COMPASS_INCOMPATIBLE_ORBIT = "Orbit: Kompass konnte nicht gestartet werden. Aktualisiert Orbit oder deaktiviert Orbit und ladet die Benutzeroberfläche neu, um den Kompass eigenständig zu nutzen.",
        CMD_COMPASS_DISABLED = "Aktiviert den Kompass in seinen Einstellungen, um den Navigationspfeil zu verwenden.",
    },
    frFR = {
        PLU_COMPASS_ARROW = "Flèche",
        PLU_COMPASS_ARROW_TITLE = "Boussole : Flèche",
        MSG_COMPASS_NOT_READY = "Les paramètres de la boussole sont indisponibles.",
        MSG_COMPASS_INCOMPATIBLE_ORBIT = "Orbit : la boussole n’a pas pu démarrer. Mettez Orbit à jour, ou désactivez Orbit et rechargez l’interface pour utiliser la boussole seule.",
        CMD_COMPASS_DISABLED = "Activez la boussole dans ses paramètres pour utiliser la flèche de navigation.",
    },
    esES = {
        PLU_COMPASS_ARROW = "Flecha",
        PLU_COMPASS_ARROW_TITLE = "Brújula: Flecha",
        MSG_COMPASS_NOT_READY = "Los ajustes de la brújula no están disponibles.",
        MSG_COMPASS_INCOMPATIBLE_ORBIT = "Orbit: No se pudo iniciar la brújula. Actualiza Orbit o desactívalo y recarga la interfaz para usar la brújula de forma independiente.",
        CMD_COMPASS_DISABLED = "Activa la brújula en sus ajustes para usar la flecha de navegación.",
    },
    ptBR = {
        PLU_COMPASS_ARROW = "Seta",
        PLU_COMPASS_ARROW_TITLE = "Bússola: Seta",
        MSG_COMPASS_NOT_READY = "As configurações da bússola estão indisponíveis.",
        MSG_COMPASS_INCOMPATIBLE_ORBIT = "Orbit: Não foi possível iniciar a bússola. Atualize o Orbit ou desative-o e recarregue a interface para usar a bússola de forma independente.",
        CMD_COMPASS_DISABLED = "Ative a bússola nas configurações para usar a seta de navegação.",
    },
    ruRU = {
        PLU_COMPASS_ARROW = "Стрелка",
        PLU_COMPASS_ARROW_TITLE = "Компас: Стрелка",
        MSG_COMPASS_NOT_READY = "Настройки компаса недоступны.",
        MSG_COMPASS_INCOMPATIBLE_ORBIT = "Orbit: Не удалось запустить компас. Обновите Orbit или отключите его и перезагрузите интерфейс, чтобы использовать компас отдельно.",
        CMD_COMPASS_DISABLED = "Включите компас в его настройках, чтобы использовать навигационную стрелку.",
    },
    koKR = {
        PLU_COMPASS_ARROW = "화살표",
        PLU_COMPASS_ARROW_TITLE = "나침반: 화살표",
        MSG_COMPASS_NOT_READY = "나침반 설정을 사용할 수 없습니다.",
        MSG_COMPASS_INCOMPATIBLE_ORBIT = "Orbit: 나침반을 시작할 수 없습니다. Orbit을 업데이트하거나 비활성화한 후 UI를 재시작하면 나침반을 독립적으로 사용할 수 있습니다.",
        CMD_COMPASS_DISABLED = "이동 방향 화살표를 사용하려면 설정에서 나침반을 활성화하세요.",
    },
    zhCN = {
        PLU_COMPASS_ARROW = "箭头",
        PLU_COMPASS_ARROW_TITLE = "指南针：箭头",
        MSG_COMPASS_NOT_READY = "罗盘设置不可用。",
        MSG_COMPASS_INCOMPATIBLE_ORBIT = "Orbit：无法启动指南针。请更新 Orbit，或禁用 Orbit 并重载界面，以独立使用指南针。",
        CMD_COMPASS_DISABLED = "请在设置中启用罗盘以使用导航箭头。",
    },
    zhTW = {
        PLU_COMPASS_ARROW = "箭頭",
        PLU_COMPASS_ARROW_TITLE = "指南針：箭頭",
        MSG_COMPASS_NOT_READY = "羅盤設定無法使用。",
        MSG_COMPASS_INCOMPATIBLE_ORBIT = "Orbit：無法啟動指南針。請更新 Orbit，或停用 Orbit 並重新載入介面，以獨立使用指南針。",
        CMD_COMPASS_DISABLED = "請在設定中啟用羅盤以使用導航箭頭。",
    },
}

local host = Addon.OrbitHost
if host then
    for key in pairs(Addon.L) do
        local value = rawget(host.L, key)
        if value ~= nil then
            Addon.L[key] = value
        end
    end
end

local locale = host and host.Localization and host.Localization.activeLocale or GetLocale()
if locale == "enGB" then
    locale = "enUS"
end
if locale == "esMX" then
    locale = "esES"
end
for key, value in pairs(STRINGS[locale] or STRINGS.enUS) do
    Addon.L[key] = value
end
if not Addon.incompatibleOrbit then
    _G.BINDING_HEADER_ORBIT_COMPASS = Addon.L.PLG_NAME_COMPASS
end
